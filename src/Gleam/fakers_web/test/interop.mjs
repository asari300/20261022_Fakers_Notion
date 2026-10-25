// 相互運用ゲート（ADR-0003 を Accepted にする条件）。
//   1. yrs（Rust）が作ったページの状態を yjs に適用でき、ブロックの形が同じ
//   2. yjs の編集（update v1）を yrs に戻して適用でき、文字が入る
// 実行: node test/interop.mjs（mise run test:interop）。cargo を子プロセスで呼ぶ。
import { execFileSync } from "node:child_process";
import assert from "node:assert/strict";
import { fileURLToPath } from "node:url";
import * as Y from "yjs";

const manifest = fileURLToPath(new URL("../../../Rust/Cargo.toml", import.meta.url));
const cargo = (example, args, input) =>
  execFileSync(
    "cargo",
    ["run", "-q", "--manifest-path", manifest, "-p", "fakers_core", "--example", example, "--", ...args],
    { input, encoding: "utf8", stdio: ["pipe", "pipe", "inherit"] },
  );
const fromHex = (s) => Uint8Array.from(s.trim().match(/../g).map((h) => parseInt(h, 16)));
const toHex = (u8) => Array.from(u8, (b) => b.toString(16).padStart(2, "0")).join("");
const snapshot = (doc) =>
  doc.getArray("blocks").toArray().map((m) => ({
    id: m.get("id"),
    type: m.get("type"),
    text: m.get("text").toString(),
    checked: m.get("checked") ?? false,
    indent: m.get("indent") ?? 0,
  }));

// 1. yrs → yjs
const stateHex = cargo("dump_page", ["Interop"]);
const doc = new Y.Doc();
Y.applyUpdate(doc, fromHex(stateHex));
const blocks = snapshot(doc);
assert.deepEqual(blocks, [
  { id: "h1", type: "heading", text: "Interop", checked: false, indent: 0 },
  { id: "p1", type: "paragraph", text: "", checked: false, indent: 0 },
]);

// 2. yjs → yrs（絵文字で UTF-16 の位置も確かめる）
const svBefore = Y.encodeStateVector(doc);
const para = doc.getArray("blocks").get(1).get("text");
para.insert(0, "hello 😀");
para.insert(8, "!"); // 😀 は UTF-16 で 2 単位なので "hello 😀" は 8
// ToDo のチェックと入れ子の深さ（Y.Map のキー。yjs の整数が yrs で読めるか）
doc.getArray("blocks").get(1).set("type", "todo");
doc.getArray("blocks").get(1).set("checked", true);
doc.getArray("blocks").get(1).set("indent", 2);
const update = Y.encodeStateAsUpdate(doc, svBefore);
const json = cargo("apply_hex", [], `${stateHex.trim()}\n${toHex(update)}\n`);
const parsed = JSON.parse(json);
assert.equal(parsed[1].text, "hello 😀!");
assert.equal(parsed[1].checked, true);
assert.equal(parsed[1].indent, 2);
assert.deepEqual(parsed, snapshot(doc));

// データベースのブロック（列と行は入れ子の Y.Array / Y.Map）。yrs の blocks_json は種類と題名だけを読む
doc.transact(() => {
  const db = new Y.Map();
  db.set("id", "d1");
  db.set("type", "database");
  db.set("text", new Y.Text("本棚"));
  const col = new Y.Map();
  col.set("id", "c1");
  col.set("name", "価格");
  col.set("type", "number");
  const row = new Y.Map();
  row.set("id", "r1");
  row.set("c1", 1.5);
  db.set("columns", Y.Array.from([col]));
  db.set("rows", Y.Array.from([row]));
  doc.getArray("blocks").push([db]);
});
const dbJson = JSON.parse(cargo("apply_hex", [], `\n${toHex(Y.encodeStateAsUpdate(doc))}\n`));
assert.deepEqual(dbJson[2], { id: "d1", type: "database", text: "本棚", checked: false, indent: 0 });

// 3. yjs の全状態をそのまま yrs に渡しても同じ
const full = cargo("apply_hex", [], `\n${toHex(Y.encodeStateAsUpdate(doc))}\n`);
assert.deepEqual(JSON.parse(full), snapshot(doc));

console.log(`OK interop: yrs→yjs ${JSON.stringify(blocks)} / yjs→yrs text=${JSON.stringify(parsed[1].text)} / update ${update.length} bytes, clientID ${doc.clientID}`);
