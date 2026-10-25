// 1 ページ分の編集セッション。Y.Doc・Socket・Channel をここで持ち、
// バイト列は Gleam 側に一切渡さない（Gleam には JSON の文字列だけを渡す）。
import * as Y from "yjs";
import { Presence, Socket } from "phoenix";

// 自分で適用したサーバ由来の更新の origin。ローカル変更と区別するのに使う。
const REMOTE = "remote";

// Uint8Array から過不足のない ArrayBuffer を作る。
// phoenix は payload.constructor === ArrayBuffer のときだけバイナリで送るため。
const toArrayBuffer = (u8) => u8.buffer.slice(u8.byteOffset, u8.byteOffset + u8.byteLength);

const isHigh = (c) => c >= 0xd800 && c <= 0xdbff;
const isLow = (c) => c >= 0xdc00 && c <= 0xdfff;

// old → new の差分を 1 か所の「削除＋挿入」で表す（位置は UTF-16 単位）。
// サロゲートペアの途中で切らないように境界を調整する。
// 戻り値は Gleam のタプル #(Int, Int, String) = JS の配列。
export function diff_text(oldText, newText) {
  const oldLen = oldText.length;
  const newLen = newText.length;
  const minLen = Math.min(oldLen, newLen);
  let start = 0;
  while (start < minLen && oldText.charCodeAt(start) === newText.charCodeAt(start)) start++;
  // 共通の先頭がサロゲートの上位で終わっていたら 1 つ戻す
  if (start > 0 && start < minLen && isHigh(oldText.charCodeAt(start - 1))) start--;
  let suffix = 0;
  while (
    suffix < minLen - start &&
    oldText.charCodeAt(oldLen - 1 - suffix) === newText.charCodeAt(newLen - 1 - suffix)
  ) suffix++;
  // 共通の末尾が下位サロゲートから始まっていたら 1 つ減らす
  if (suffix > 0 && isLow(oldText.charCodeAt(oldLen - suffix))) suffix--;
  const delLen = oldLen - start - suffix;
  const inserted = newText.slice(start, newLen - suffix);
  return [start, delLen, inserted];
}

// Y.Array("blocks") を Gleam に渡す JSON の形へ
function snapshot(doc) {
  return JSON.stringify(
    doc.getArray("blocks").toArray().map((m) => ({
      id: m.get("id"),
      type: m.get("type"),
      text: m.get("text")?.toString() ?? "",
      // 他人が壊れた値を書いても一覧ごと読めなくならないよう、ここで形を揃える
      checked: m.get("checked") === true,
      indent: Number.isSafeInteger(m.get("indent")) ? Math.max(0, m.get("indent")) : 0,
      table: m.get("type") === "database" ? tableJson(m) : undefined,
    })),
  );
}

// データベースのブロックの列と行（fakers_shared/database の形）。行の Y.Map は "id" と列の id → 値
const isCellValue = (v) =>
  typeof v === "string" || typeof v === "boolean" || (typeof v === "number" && Number.isFinite(v));
const hasId = (m) => m instanceof Y.Map && typeof m.get("id") === "string";
function tableJson(m) {
  const cols = m.get("columns");
  const rows = m.get("rows");
  if (!(cols instanceof Y.Array) || !(rows instanceof Y.Array)) return undefined;
  return {
    columns: cols.toArray().filter(hasId).map((c) => ({
      id: c.get("id"),
      name: String(c.get("name") ?? ""),
      type: String(c.get("type") ?? "text"),
    })),
    rows: rows.toArray().filter(hasId).map((r) => ({
      id: r.get("id"),
      cells: Object.fromEntries([...r.entries()].filter(([k, v]) => k !== "id" && isCellValue(v))),
    })),
  };
}

function newColumn(name, type) {
  const c = new Y.Map();
  c.set("id", crypto.randomUUID());
  c.set("name", name);
  c.set("type", type);
  return c;
}

function findIndex(blocks, blockId) {
  const items = blocks.toArray();
  for (let i = 0; i < items.length; i++) {
    if (items[i].get("id") === blockId) return i;
  }
  return -1;
}

// フォーカス中のブロック入力欄の選択範囲を Y.Text 上の相対位置で覚え、
// リモート更新を適用した後に入力欄へ書き戻す（値を先に揃えておくと、
// Lustre が同じ値を設定してもキャレットは動かない）。
function applyRemote(doc, update) {
  const el = typeof document === "undefined" ? null : document.activeElement;
  const blockId = el?.id?.startsWith("block-") ? el.id.slice(6) : null;
  const block = blockId ? findBlockIn(doc, blockId) : null;
  if (!block || el.selectionStart == null) {
    Y.applyUpdate(doc, update, REMOTE);
    return;
  }
  const text = block.get("text");
  const dir = el.selectionDirection ?? "none";
  const rel = [el.selectionStart, el.selectionEnd].map((i) =>
    Y.createRelativePositionFromTypeIndex(text, i),
  );
  Y.applyUpdate(doc, update, REMOTE);
  const next = text.toString();
  if (next === el.value) return;
  const [a, b] = rel.map((r) => Y.createAbsolutePositionFromRelativePosition(r, doc)?.index ?? next.length);
  el.value = next;
  el.setSelectionRange(a, b, dir);
}

function findBlockIn(doc, blockId) {
  const blocks = doc.getArray("blocks");
  const i = findIndex(blocks, blockId);
  return i < 0 ? null : blocks.get(i);
}

// 相対位置（Uint8Array）と base64 の行き来。Presence の meta に文字列で載せるため
const b64 = (u8) => btoa(String.fromCharCode(...u8));
const unb64 = (s) => Uint8Array.from(atob(s), (c) => c.charCodeAt(0));

// タブごとの表示名。sessionStorage が使えなければその場限りの名前
function myName() {
  const fallback = "ゲスト " + Math.random().toString(16).slice(2, 6);
  try {
    let n = sessionStorage.getItem("fakers-name");
    if (!n) sessionStorage.setItem("fakers-name", (n = fallback));
    return n;
  } catch {
    return fallback;
  }
}

// user_id から決まる色。全員の画面で同じ人は同じ色になる
function colorOf(id) {
  let h = 0;
  for (const c of id) h = (h * 31 + c.charCodeAt(0)) >>> 0;
  return `hsl(${h % 360} 70% 45%)`;
}

// 自分の選択範囲を Y.Text 上の相対位置で表す（相手の手元の編集でずれない）。
// フォーカスがブロックに無ければ {}（カーソルを消す）
function cursorPayload(doc) {
  const el = document.activeElement;
  const blockId = el?.id?.startsWith("block-") ? el.id.slice(6) : null;
  const block = blockId ? findBlockIn(doc, blockId) : null;
  if (!block || el.selectionStart == null) return {};
  const text = block.get("text");
  const enc = (i) => b64(Y.encodeRelativePosition(Y.createRelativePositionFromTypeIndex(text, i)));
  const back = el.selectionDirection === "backward";
  return {
    block: blockId,
    anchor: enc(back ? el.selectionEnd : el.selectionStart),
    head: enc(back ? el.selectionStart : el.selectionEnd),
  };
}

// 他人の meta の相対位置を手元の文書の位置へ。壊れていれば null
function toIndex(doc, s) {
  try {
    return Y.createAbsolutePositionFromRelativePosition(Y.decodeRelativePosition(unb64(s)), doc)?.index ?? null;
  } catch {
    return null;
  }
}

// 入力欄で文字列 value の位置 i にある文字の座標 {x, y, h}（ビューポート基準）。canvas で文字幅を測る。
// textarea（コード）は折り返さない前提で、改行の数から行を決める
let measureCtx = null;
function caretAt(el, value, i) {
  measureCtx ??= document.createElement("canvas").getContext("2d");
  const cs = getComputedStyle(el);
  measureCtx.font = `${cs.fontStyle} ${cs.fontWeight} ${cs.fontSize} ${cs.fontFamily}`;
  const r = el.getBoundingClientRect();
  const left = r.left + parseFloat(cs.borderLeftWidth) + parseFloat(cs.paddingLeft) - el.scrollLeft;
  const lines = value.slice(0, i).split("\n");
  const x = left + measureCtx.measureText(lines.at(-1)).width;
  if (el.tagName !== "TEXTAREA") return { x, y: r.top, h: r.height };
  const lh = parseFloat(cs.lineHeight) || parseFloat(cs.fontSize) * 1.5;
  const top = r.top + parseFloat(cs.borderTopWidth) + parseFloat(cs.paddingTop) - el.scrollTop;
  return { x, y: top + (lines.length - 1) * lh, h: lh };
}

// 他人のカーソルと選択範囲を、画面に固定した透明な層へ描き直す
function paintCursors(session) {
  const layer = session.layer;
  layer.replaceChildren();
  for (const p of session.peers) {
    const c = p.cursor;
    const el = c && document.getElementById("block-" + c.block);
    if (!el) continue;
    const a = toIndex(session.doc, c.anchor);
    const h = toIndex(session.doc, c.head);
    if (a == null || h == null) continue;
    // 入力欄の値は Lustre がこの後で書き換えることがあるので、文書の方を測る
    const value = findBlockIn(session.doc, c.block)?.get("text")?.toString() ?? el.value;
    const r = el.getBoundingClientRect();
    const pa = caretAt(el, value, Math.min(a, value.length));
    const ph = caretAt(el, value, Math.min(h, value.length));
    const box = (cls, x, y, w, ht) => {
      const d = document.createElement("div");
      d.className = cls;
      d.style.cssText = `left:${x}px;top:${y}px;width:${w}px;height:${ht}px;--peer:${p.color}`;
      layer.append(d);
      return d;
    };
    // 選択範囲の帯は入力欄の中に収める（横にスクロールした分は切る）。複数行にまたがる選択は帯を描かない
    const sl = Math.max(Math.min(pa.x, ph.x), r.left);
    const sr = Math.min(Math.max(pa.x, ph.x), r.right);
    if (a !== h && pa.y === ph.y && sl < sr) box("remote-sel", sl, ph.y, sr - sl, ph.h);
    // 横にスクロールして入力欄の外に出たキャレットは描かない。縦は見ない: textarea は行数ぶんの
    // rows を持ち縦にスクロールしないが、その rows は Lustre がこの後で増やすので、今の高さと比べると新しい行を捨ててしまう
    if (ph.x < r.left || ph.x > r.right) continue;
    const caret = box("remote-caret", ph.x, ph.y, 2, ph.h);
    caret.dataset.peer = p.name;
    caret.dataset.index = String(h);
    const label = document.createElement("span");
    label.className = "remote-label";
    label.textContent = p.name;
    caret.append(label);
  }
}

function findBlock(session, blockId) {
  const blocks = session.doc.getArray("blocks");
  const i = findIndex(blocks, blockId);
  return i < 0 ? null : blocks.get(i);
}

export function open(docId, onBlocks, onStatus, onPeers) {
  const doc = new Y.Doc();
  const socket = new Socket("/socket", {});
  const channel = socket.channel("doc:" + docId, { name: myName() });
  const presence = new Presence(channel);
  const layer = document.createElement("div");
  layer.className = "remote-layer";
  document.body.append(layer);
  const session = {
    doc, socket, channel, layer, closed: false, scheduled: false,
    me: null, peers: [], lastCursor: null, cursorPending: false, paintPending: false,
  };

  // カーソルの送信と描画は 1 フレームに 1 回にまとめる
  const paint = () => {
    if (session.paintPending) return;
    session.paintPending = true;
    requestAnimationFrame(() => {
      session.paintPending = false;
      if (!session.closed) paintCursors(session);
    });
  };
  const sendCursor = () => {
    if (session.cursorPending) return;
    session.cursorPending = true;
    requestAnimationFrame(() => {
      session.cursorPending = false;
      if (session.closed || channel.state !== "joined") return;
      const payload = cursorPayload(doc);
      const key = JSON.stringify(payload);
      // 相対位置は手前に打った文字では変わらないので、入力のたびには送らない
      if (key === session.lastCursor) return;
      session.lastCursor = key;
      channel.push("cursor", payload);
    });
  };
  session.listeners = [
    ...["selectionchange", "focusin", "focusout", "keyup", "mouseup"].map((t) => [document, t, sendCursor]),
    [window, "resize", paint],
    [document, "scroll", paint, true],
  ];
  for (const [target, type, fn, capture] of session.listeners) target.addEventListener(type, fn, capture);

  presence.onSync(() => {
    session.peers = presence
      .list((id, { metas: [m] }) => ({ id, name: m.name, color: colorOf(id), cursor: m.cursor }))
      .filter((p) => p.id !== session.me);
    if (!session.closed) onPeers(JSON.stringify(session.peers.map(({ id, name, color }) => ({ id, name, color }))));
    paint();
  });

  const status = (s) => {
    if (!session.closed) onStatus(s);
  };
  // 同じ tick 内の複数の変更を 1 回の通知にまとめる
  const notify = () => {
    if (session.closed || session.scheduled) return;
    session.scheduled = true;
    queueMicrotask(() => {
      session.scheduled = false;
      if (!session.closed) onBlocks(snapshot(doc));
    });
  };
  const pushUpdate = (u8) => {
    channel
      .push("update", toArrayBuffer(u8))
      .receive("error", (r) => status("error: " + (r?.reason ?? JSON.stringify(r))))
      .receive("timeout", () => status("error: timeout"));
  };

  doc.on("update", (update, origin) => {
    notify();
    paint();
    if (origin === REMOTE) return;
    // 未接続中の変更は送らない。次の sync の後の追いつき処理でまとめて送る
    if (channel.state === "joined") pushUpdate(update);
  });

  channel.on("sync", (buf) => {
    const state = new Uint8Array(buf);
    applyRemote(doc, state);
    // 切断中に作った変更のうち、サーバが持っていない分を送り返す
    const sv = Y.encodeStateVectorFromUpdate(state);
    const missing = Y.encodeStateAsUpdate(doc, sv);
    if (missing.length > 2) pushUpdate(missing);
    notify();
  });
  channel.on("update", (buf) => {
    applyRemote(doc, new Uint8Array(buf));
  });

  channel.onError((reason) => status("error: " + (reason?.reason ?? reason ?? "channel")));
  channel.onClose(() => status("closed"));
  socket.onError(() => status("error: connection"));

  status("connecting");
  socket.connect();
  channel
    .join()
    .receive("ok", (r) => {
      // 再接続のたびに user_id が変わるので、カーソルも送り直す
      session.me = r.user_id;
      session.lastCursor = null;
      status("joined");
      sendCursor();
    })
    .receive("error", (r) => status("error: " + (r?.reason ?? JSON.stringify(r))))
    .receive("timeout", () => status("error: timeout"));

  return session;
}

export function set_text(session, blockId, newText) {
  const block = findBlock(session, blockId);
  if (!block) return undefined;
  const text = block.get("text");
  const [start, delLen, inserted] = diff_text(text.toString(), newText);
  if (delLen === 0 && inserted === "") return undefined;
  session.doc.transact(() => {
    if (delLen > 0) text.delete(start, delLen);
    if (inserted !== "") text.insert(start, inserted);
  });
  return undefined;
}

export function insert_block_after(session, blockId, kind, indent) {
  const id = crypto.randomUUID();
  const blocks = session.doc.getArray("blocks");
  session.doc.transact(() => {
    const m = new Y.Map();
    m.set("id", id);
    m.set("type", kind);
    m.set("text", new Y.Text());
    if (indent > 0) m.set("indent", indent);
    const i = findIndex(blocks, blockId);
    // 見つからなければ末尾に足す
    blocks.insert(i < 0 ? blocks.length : i + 1, [m]);
  });
  return id;
}

export function set_kind(session, blockId, kind) {
  const block = findBlock(session, blockId);
  if (!block || block.get("type") === kind) return undefined;
  session.doc.transact(() => {
    block.set("type", kind);
    // データベースにしたら列 1 つ・行 0 の表を作る。種類を戻しても表は消さない（もう一度選べば戻る）
    if (kind === "database" && !(block.get("columns") instanceof Y.Array)) {
      const cols = new Y.Array();
      cols.push([newColumn("名前", "text")]);
      block.set("columns", cols);
      block.set("rows", new Y.Array());
    }
  });
  return undefined;
}

// データベースの列と行。表が無いブロックや、見つからない id には何もしない
function tableOf(session, blockId) {
  const block = findBlock(session, blockId);
  const cols = block?.get("columns");
  const rows = block?.get("rows");
  return cols instanceof Y.Array && rows instanceof Y.Array ? { cols, rows } : null;
}

export function add_column(session, blockId, name, type) {
  const t = tableOf(session, blockId);
  if (!t) return "";
  const c = newColumn(name, type);
  t.cols.push([c]);
  return c.get("id");
}

// key は "name" か "type"
export function set_column(session, blockId, colId, key, value) {
  const t = tableOf(session, blockId);
  const i = t ? findIndex(t.cols, colId) : -1;
  if (i >= 0) t.cols.get(i).set(key, value);
  return undefined;
}

export function delete_column(session, blockId, colId) {
  const t = tableOf(session, blockId);
  const i = t ? findIndex(t.cols, colId) : -1;
  if (i < 0) return undefined;
  session.doc.transact(() => {
    t.cols.delete(i, 1);
    for (const r of t.rows.toArray()) if (r instanceof Y.Map) r.delete(colId);
  });
  return undefined;
}

export function add_row(session, blockId) {
  const t = tableOf(session, blockId);
  if (!t) return "";
  const r = new Y.Map();
  r.set("id", crypto.randomUUID());
  t.rows.push([r]);
  return r.get("id");
}

export function delete_row(session, blockId, rowId) {
  const t = tableOf(session, blockId);
  const i = t ? findIndex(t.rows, rowId) : -1;
  if (i >= 0) t.rows.delete(i, 1);
  return undefined;
}

// value は JSON の文字列。null ならセルを消す。
// shortcut: セルは文字列ごと後勝ち（Y.Text にしない）。同じセルを 2 人が同時に打つと片方が消える。困ったら Y.Text にする
export function set_cell(session, blockId, rowId, colId, valueJson) {
  const t = tableOf(session, blockId);
  const i = t ? findIndex(t.rows, rowId) : -1;
  if (i < 0) return undefined;
  const v = JSON.parse(valueJson);
  const row = t.rows.get(i);
  if (v === null) row.delete(colId);
  else if (isCellValue(v) && row.get(colId) !== v) row.set(colId, v);
  return undefined;
}

export function set_checked(session, blockId, checked) {
  findBlock(session, blockId)?.set("checked", checked);
  return undefined;
}

export function set_indent(session, blockId, indent) {
  findBlock(session, blockId)?.set("indent", indent);
  return undefined;
}

export function delete_block(session, blockId) {
  const blocks = session.doc.getArray("blocks");
  // 最後の 1 ブロックは消さない
  if (blocks.length <= 1) return undefined;
  const i = findIndex(blocks, blockId);
  if (i >= 0) blocks.delete(i, 1);
  return undefined;
}

export function close(session) {
  if (session.closed) return undefined;
  session.closed = true;
  for (const [target, type, fn, capture] of session.listeners) target.removeEventListener(type, fn, capture);
  session.layer.remove();
  session.channel.leave();
  session.socket.disconnect();
  session.doc.destroy();
  return undefined;
}

// 新しく作ったブロックの入力欄へ、描画が終わってからフォーカスを移す
export function focus_block(blockId) {
  if (typeof document === "undefined") return undefined;
  requestAnimationFrame(() => {
    const el = document.getElementById("block-" + blockId);
    if (el) el.focus();
  });
  return undefined;
}
