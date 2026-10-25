# S011 `database-table`

| | |
| --- | --- |
| 日付 | 2026-10-25 |
| ブランチ | `feature/s011-database-table` |
| worktree | `.git-worktree/s011-database-table`（実体は `/mnt/usb_sd64c/Fakers_Notion/worktrees/s011-database-table`） |
| Phase | P3 |
| セッション文書 | `doc/sessions/S011-database-table/` |
| セッション記録 | `log/sessions/2026-10-24-c03403db-ff3c-4ac5-ac00-19e7f00f5334.md`（S007〜S010 と同じセッション） |

## 依頼

S009 / S010 を締めた後に「作業をつづけて。」。P3 の 2 回目として、データベースのブロックとテーブルのビューを作った。

## 決めたこと

- **データベースはページの Y.Doc の中のブロック**（[ADR-0008](../../doc/adr/0008-database-in-page-doc.md)）。features.md に方針が既にあったので、ユーザーには聞かずにそのまま進めた。独立した文書にする案（リンクドビューやリレーションに向く）は、必要になったら移す。
- 列と行は `Y.Array` の `Y.Map`、セルは値をそのまま置いて後勝ち（shortcut。同じセルの同時入力は片方が消える）。
- 列の型は テキスト・数値・チェック の 3 つから始めた（既定のまま進めた）。
- `Block` の形を変えず、表は別のデコーダ（`database.decode_tables`）で同じ JSON から読む。Erlang のタプルが変わらないので、Elixir と Rust の `blocks_json` を触らずに済んだ。
- 数値のセルは途中の入力を `Model.number_draft` に持つ。最初は「読めないときは今の値を書き直す」にしたが、E2E で "1." → "5" が "15" になった（Lustre が入力欄の値を描画の値へ戻す）。
- サブエージェントは使っていない（層をまたいで互いに依存していた）。

## やったこと

- `src/Gleam/fakers_shared/src/fakers_shared/block.gleam`: `Database` の種類。
- `src/Gleam/fakers_shared/src/fakers_shared/database.gleam`（新規）: `PropType` / `Column` / `Cell` / `Row` / `Table`、`cell`（列の型と合う値だけ）、`cell_to_json`、`decode_tables`。
- `src/Gleam/fakers_web/src/fakers_web/session.ffi.mjs` と `session.gleam`: `snapshot` の `table`、`set_kind` で表を作る、`add_column` / `set_column` / `delete_column` / `add_row` / `delete_row` / `set_cell`。
- `src/Gleam/fakers_web/src/fakers_web.gleam`: `Model.tables` と `number_draft`、列・行・セルのメッセージ、`view_table` / `view_cell`、`parse_number` / `number_to_string`。
- `src/Gleam/fakers_web/app.css`: 表の見た目。
- テスト: shared に表の JSON（知らない型・壊れた値・型違い）、web に数値の読み書き、interop に yjs の表のブロック、E2E に 10。
- 文書: ADR-0008、architecture.md の 4 章と 9 章、features.md、roadmap.md（S011 の節）、`doc/sessions/S011-database-table/`、索引。

## 検証

- 1 回目の E2E は 10 の数値のセルで失敗（`1.5` のはずが `15`）。`number_draft` を足して通した。
- 画面: ライト・ダーク・幅 390 px のスクリーンショット。列の型の選択欄の幅を 64 → 84 px に直した。
- `mise run test`（全部）: Rust 5 + 7 passed、interop OK（yjs の表のブロックを yrs が読む）、Gleam 9+9+13 passed、Elixir 21 tests 0 failures、E2E OK（tab1→tab2 29 ms、再接続後 3421 ms、10 のデータベースを含む）。
- src の差分: 11 files changed, 745 insertions(+), 13 deletions(-)。
- `check_docs.py`: 全デッキ OK / 文書 53 件・リンク 208 件中の切れ 0 件。`render_slides.py`: デッキ 11 件 / 問題 0 件（S04 を目で確認）。
- セッション記録の `--check`: 取りこぼし 0 件。ステージした差分の漏洩検査: 0 件。

## 残したこと

- フィルタとソート、ボードとリストのビュー、フォーミュラの列（評価をどこで行うか）、日付と選択の列の型。
- セルは後勝ち（同じセルの同時入力は片方が消える）。セルに相手のキャレットは描かない。数値のセルの下書き中は相手の変更が見えない（フォーカスを外すと見える）。
- 再起動後に表が残ることは E2E で確かめていない（文書ごと保存するので残るはず【未確認】）。
- `mix deps.get` の security advisories【未確認】。日本語入力の変換中のリモート更新（P2 の残り）。
