# ADR-0007 フォーミュラは Notion の formula 2.0 の部分集合を Rust の純関数で実装する

- 状態: **Accepted**（2026-10-25、S009。例題集が Rust のテストで通った）。

## 背景

- P3 の完了条件の 1 つが「フォーミュラの例題集が Rust のテストで通る」（[roadmap.md](../roadmap.md)）。[features.md](../features.md) の方針は「Rust の字句解析・構文解析・型検査・評価器。NIF と、P5 で WASM の両側で同じ実装」。
- データベースのデータモデル（行・プロパティの持ち方）はまだ決めていない。フォーミュラはそれに依らずに作れる。

## 決定

- **`fakers_core::formula` に置く**（別の crate にしない）。依存は増えない（`thiserror` だけ）。状態を持たない純関数で、[ADR-0003](0003-crdt-yjs-yrs.md) と同じ形。
- **API は 2 段**: `compile(src, schema) -> Formula`（字句解析・構文解析・型検査）と `Formula::eval(row) -> Value`。プロパティの型が分かった時点で一度だけ検査し、行ごとには評価だけをする。
- **言語は Notion の formula 2.0 の書き方に寄せた部分集合**: `prop("名前")`、数値・文字列・`true` / `false`、`+ - * / % ^`、比較、`and` / `or` / `not`（`&&` / `||` / `!` も可）、`c ? a : b` と `if(c, a, b)`、関数 `length lower upper contains format toNumber empty round floor ceil abs sqrt min max`。
- **型は 数値・テキスト・真偽値 の 3 つで、暗黙の変換をしない**（`1 + "a"` は型エラー。`format()` で明示する）。
- **行に無いプロパティは空の値**（0・空文字・false）として読む。`empty(x)` はこの空の値と等しいかを返す。行の値の型が schema と違うときは実行時エラー。
- **数値が有限でなくなったら実行時エラー**（0 での割り算・負の数の平方根・桁あふれ）。`toNumber` で読めない文字列も実行時エラー。
- **入れ子の深さを 100 で打ち切る**。型検査と評価は再帰するので、利用者の書いた深い式で NIF のスタック（dirty CPU scheduler の既定は 40 kword。<https://www.erlang.org/doc/apps/erts/erl_cmd.html> の `+sssdcpu`、2026-10-25 確認）があふれて VM ごと落ちるのを防ぐ。

## 結果

- 例題 42 題・構文と型のエラー 22 題・実行時エラー 4 題・深さの上限を `crates/fakers_core/tests/formula.rs` で検査する。エラーは位置（先頭からの文字数）を返す。
- 日付の型・リスト・メソッド記法（`prop("x").length()`）・`let`・リレーションとロールアップは無い。データベースの型（日付・選択）を足すときに広げる。
- NIF の関数と UI への組み込みは、データベースのデータモデルを決めるセッションで行う。
