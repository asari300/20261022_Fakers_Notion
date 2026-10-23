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
    })),
  );
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

// 入力欄の文字位置 i の x 座標（ビューポート基準）。canvas で文字幅を測る
let measureCtx = null;
function caretX(el, i) {
  measureCtx ??= document.createElement("canvas").getContext("2d");
  const cs = getComputedStyle(el);
  measureCtx.font = `${cs.fontStyle} ${cs.fontWeight} ${cs.fontSize} ${cs.fontFamily}`;
  const r = el.getBoundingClientRect();
  const left = r.left + parseFloat(cs.borderLeftWidth) + parseFloat(cs.paddingLeft) - el.scrollLeft;
  return left + measureCtx.measureText(el.value.slice(0, i)).width;
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
    const len = el.value.length;
    const r = el.getBoundingClientRect();
    const xa = caretX(el, Math.min(a, len));
    const xh = caretX(el, Math.min(h, len));
    const box = (cls, x, w) => {
      const d = document.createElement("div");
      d.className = cls;
      d.style.cssText = `left:${x}px;top:${r.top}px;width:${w}px;height:${r.height}px;--peer:${p.color}`;
      layer.append(d);
      return d;
    };
    if (a !== h) box("remote-sel", Math.min(xa, xh), Math.abs(xh - xa));
    // 入力欄の外へスクロールしたキャレットは描かない
    if (xh < r.left || xh > r.right) continue;
    const caret = box("remote-caret", xh, 2);
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

export function insert_block_after(session, blockId, kind) {
  const id = crypto.randomUUID();
  const blocks = session.doc.getArray("blocks");
  session.doc.transact(() => {
    const m = new Y.Map();
    m.set("id", id);
    m.set("type", kind);
    m.set("text", new Y.Text());
    const i = findIndex(blocks, blockId);
    // 見つからなければ末尾に足す
    blocks.insert(i < 0 ? blocks.length : i + 1, [m]);
  });
  return id;
}

export function set_kind(session, blockId, kind) {
  const block = findBlock(session, blockId);
  if (block && block.get("type") !== kind) block.set("type", kind);
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
