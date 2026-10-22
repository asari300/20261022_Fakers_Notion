// 1 ページ分の編集セッション。Y.Doc・Socket・Channel をここで持ち、
// バイト列は Gleam 側に一切渡さない（Gleam には JSON の文字列だけを渡す）。
import * as Y from "yjs";
import { Socket } from "phoenix";

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

function findBlock(session, blockId) {
  const blocks = session.doc.getArray("blocks");
  const i = findIndex(blocks, blockId);
  return i < 0 ? null : blocks.get(i);
}

export function open(docId, onBlocks, onStatus) {
  const doc = new Y.Doc();
  const socket = new Socket("/socket", {});
  const channel = socket.channel("doc:" + docId, {});
  const session = { doc, socket, channel, closed: false, scheduled: false };

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
    if (origin === REMOTE) return;
    // 未接続中の変更は送らない。次の sync の後の追いつき処理でまとめて送る
    if (channel.state === "joined") pushUpdate(update);
  });

  channel.on("sync", (buf) => {
    const state = new Uint8Array(buf);
    Y.applyUpdate(doc, state, REMOTE);
    // 切断中に作った変更のうち、サーバが持っていない分を送り返す
    const sv = Y.encodeStateVectorFromUpdate(state);
    const missing = Y.encodeStateAsUpdate(doc, sv);
    if (missing.length > 2) pushUpdate(missing);
    notify();
  });
  channel.on("update", (buf) => {
    Y.applyUpdate(doc, new Uint8Array(buf), REMOTE);
  });

  channel.onError((reason) => status("error: " + (reason?.reason ?? reason ?? "channel")));
  channel.onClose(() => status("closed"));
  socket.onError(() => status("error: connection"));

  status("connecting");
  socket.connect();
  channel
    .join()
    .receive("ok", () => status("joined"))
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
