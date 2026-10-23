# Fakers Notion ロードマップ

- 版: v0（2026-10-22、S001）。
- **P** は開発の段階（Phase）、**S** はセッション番号（`doc/sessions/SNNN-*`）。
- 1 つの Phase は複数のセッションにまたがる。セッションの数は目安。

## 全体

```mermaid
flowchart LR
  P0[P0 運用基盤] --> P1[P1 骨組みと縦スライス] --> P2[P2 共同編集の品質] --> P3[P3 データベースとフォーミュラ]
  P3 --> P4[P4 ワークスペースと権限] --> P5[P5 分散とホットスワップ] --> P6[P6 検索・エクスポート]
```

## Phase ごとの範囲と完了条件

| Phase | 範囲 | 完了条件 | 目安 |
| --- | --- | --- | --- |
| **P0 運用基盤**（S001 で完了） | CLAUDE.md、スキル、セッション記録のフック、正典の文書、ADR、調査、P1 の計画 | フックが伏せ字版を出力する。リンク切れが 0 件。P1 の計画が ADR と調査に裏付けを持つ | S001 |
| **P1 骨組みと縦スライス**（S002 で縦スライスまで完了。残りは CI とライセンス） | `mise.toml` のタスク、Rust workspace（`fakers_core`・`fakers_nif`）、Gleam（`fakers_shared`・`fakers_web`）、Phoenix（`fakers`）。ページの作成、ブロックの編集、リアルタイム同期、SQLite への永続化。CI。ライセンス | `mise run test` が 3 言語とも通る。2 つのタブで片方の編集がもう片方に即時反映される。サーバを再起動しても内容が残る。yrs → yjs の相互運用ゲートが通り、[ADR-0003](adr/0003-crdt-yjs-yrs.md) と [ADR-0004](adr/0004-gleam-integration.md) が Accepted になる。CI（GitHub Actions）が main で通る。ライセンスを決める | 2〜3 回（S002 で縦スライス、S003 で CI とライセンス） |
| **P2 共同編集の品質** | Presence とカーソル、見出しブロックと `title` 列の同期、キャレットを保つ編集（contenteditable）、切断と再接続のテスト、ブロックの種類の追加（リスト・ToDo・コード・引用・区切り・トグル） | 2 クライアントの同時編集が収束し、入力中のキャレットが飛ばない。再接続後に切断中の差分が復元される | 3 回 |
| **P3 データベースとフォーミュラ** | Notion 風のデータベース（テーブル・ボード・リストのビュー）、プロパティ、フィルタとソート、フォーミュラ言語（Rust の字句解析・構文解析・型検査・評価） | フォーミュラの例題集が Rust のテストで通る。ビューの切り替えとフィルタが UI で動く | 4 回 |
| **P4 ワークスペースと権限** | ユーザー、認証、サイドバーとページの階層、共有、権限 | 2 ユーザーで権限の違いが効く | 3 回 |
| **P5 分散とホットスワップ** | libcluster と Horde による文書プロセスの分散、Postgres への移行、OTP リリースと relup、Rust コアの WASM 化（クライアントとサーバで同じ実装） | 2 ノードで同じ文書を編集でき、ノードを落としても文書プロセスが引き継がれる。接続を切らずに `DocumentServer` を差し替えられる | 4 回 |
| **P6 検索・エクスポート・インポート** | 全文検索（tantivy）、Markdown / HTML のエクスポート、Markdown のインポート | 検索が 100 ms 未満。エクスポートの往復で内容が保たれる | 2 回 |

## 進み具合

### S001（P0、2026-10-22）で済んだこと

- 運用の型を兄弟リポジトリ GlobeMode から移した: [CLAUDE.md](../CLAUDE.md)、スキル 3 つ（start-session / finish-session / session-docs）、セッション記録のフック、`log/`、`doc/` の構成、スライドの共通 CSS と JS。
- 正典の文書 v0（[architecture.md](architecture.md)、[features.md](features.md)、この文書）と ADR 5 本（[adr/](adr/)）、調査の記録 [research/stack.md](research/stack.md)。
- `mise.toml`（ツールの版、`doctor`、`docs:check`）。Python パッケージを `src/Python/mod/fakers_notion` に改名した。
- P1 の計画（下）。前提の調査は Plan エージェント（Opus、effort medium）が行い、版と API は出典つきで [research/stack.md](research/stack.md) に残した。

### S002 の計画（P1 の 1 回目: 骨組みと縦スライス）

完了時の姿:

- `mise run test` で Rust / Gleam（両ターゲット）/ Elixir のテストが全部通る。
- `mise run dev` で <http://localhost:4000> が開き、ページを作成し、2 つのタブで同じページを開いて片方で打った文字がもう片方に即時反映される。サーバを再起動しても内容が残る。

順序（各ステップでリポジトリを green に保つ）:

1. `mise.toml` に `setup` / `build` / `test` / `dev` のタスク、`.gitignore` の追加。
2. Rust workspace（`src/Rust`）と `fakers_core`（yrs 0.28、`small-client`、`OffsetKind::Utf16`）とテスト（同時編集の収束、不正な update、UTF-16）。
3. **相互運用ゲート**: `fakers_web/package.json`（yjs 13.6.33、phoenix、esbuild）を作り、`cargo run --example dump_page | node test/interop.mjs` で yrs の状態を yjs に適用できることを確かめる。失敗したら UI に進む前に `small-client` を見直す。
4. `fakers_shared`（Block・BlockKind・PageSummary の型とデコーダ）と両ターゲットのテスト。
5. `mix phx.new src/Elixir/fakers --database sqlite3 --binary-id --no-html --no-live --no-assets --no-mailer --no-gettext --no-dashboard --no-agents-md --no-install`、`ecto_sqlite3 ~> 0.26`、`mix phx.gen.channel Document`。
6. `fakers_nif`（Rustler 0.38、全部 `DirtyCpu`）と `Fakers.Native`、Rust → Erlang のテスト。
7. `mix.exs` の `Mix.Tasks.Compile.GleamShared` と、Rust → Erlang → Gleam のデコードテスト。
8. `Document` schema と migration、`Fakers.Documents`、`DocumentServer`（Registry + DynamicSupervisor、1000 ms の flush、10 分の idle、`code_change/3`）とテスト。
9. `UserSocket`、`DocumentChannel`（join → `sync` のバイナリ push、`update` のバイナリ受信 → NIF でマージ → `broadcast_from!`）とテスト（再起動後の復元を含む）。
10. JSON API（`GET/POST /api/pages`）、`index.html` の配信、catch-all ルート。
11. Lustre SPA: ページ一覧・作成・開く・ブロック編集・Enter で新ブロック・種別トグル。FFI は `session.ffi.mjs` に閉じ込める。`build:web`（gleam build → esbuild）。
12. `mise run build | test | dev` の仕上げ、2 タブの手動確認、README の更新。

設計の詳細は [architecture.md](architecture.md)、判断の理由は [ADR-0002](adr/0002-language-roles.md)〜[ADR-0005](adr/0005-persistence-sqlite.md)、版と API の根拠は [research/stack.md](research/stack.md)。

### S002（P1 の 1 回目、2026-10-22）で済んだこと

- 計画の 12 段をすべて実装した。`mise run test` で Rust（7 本）、相互運用ゲート、Gleam（fakers_shared 6 本 × 2 ターゲット、fakers_web 10 本）、Elixir（19 本）、2 タブの E2E が通る。
- **相互運用ゲートを両方向で通した**（yrs → yjs、yjs → yrs、絵文字を含む）。[ADR-0003](adr/0003-crdt-yjs-yrs.md) と [ADR-0004](adr/0004-gleam-integration.md) を Accepted にした。
- Rust: `src/Rust` の workspace、`fakers_core`（yrs 0.28、`small-client`、UTF-16、純関数 6 つ）、`fakers_nif`（Rustler 0.38、全部 DirtyCpu）。yrs のビルドは RPi で約 22 s。
- Elixir: Phoenix 1.8.16（sqlite3、HTML 無し）、`Fakers.Native`、`Mix.Tasks.Compile.GleamShared`、`Documents` と `DocumentServer`（Registry + DynamicSupervisor、debounce の flush、idle 停止、`code_change/3`）、`DocumentChannel`（バイナリの sync / update）、`/api/pages`、`index.html` の配信。exqlite は aarch64 のプリビルド NIF が取れた。
- Gleam: `fakers_shared`（Block / PageSummary）、`fakers_web`（Lustre 5.7.1 の SPA、FFI の `session.ffi.mjs` が Y.Doc と Socket を所有、ハッシュのルーティング）。esbuild で 507.6 KB に束ねる。
- E2E: `src/Python/e2e/two_tabs.py`（Playwright）。タブ 1 → タブ 2 の反映は約 5 ms。サーバ再起動後も内容が残る。
- SPA の実装は Opus（effort medium）のサブエージェントに任せた（約 3 分、ツール呼び出し 12 回）。

### S003（P1 の 2 回目、2026-10-22）で済んだこと

- ライセンスを MIT OR Apache-2.0 に決めた（ユーザー）。`LICENSE-MIT` / `LICENSE-APACHE` と各マニフェストの license 欄。[ADR-0006](adr/0006-license-and-ci.md)。
- CI（`.github/workflows/ci.yml`）を足し、main で成功した（run 39760909180: test 2 分 23 秒、docs 58 秒）。**P1 の完了条件はすべて満たした。**

### S003 以降の候補（P1 の残り・旧）

- CI（GitHub Actions、aarch64 ではなく x86_64 の runner。差分だけを検査する GlobeMode の ADR-0006 の方式を移すかは、そのときに決める）。
- ライセンスの決定（未定。GlobeMode は MIT OR Apache-2.0）。
- `rustler` の Hex 版が 0.39 になったら crate と揃えて上げる。
- lustre_dev_tools を使いたくなったら、まず 16K ページのカーネルで Bun が動くかを試す（[research/stack.md](research/stack.md)）。

### S004（運用、2026-10-23）で済んだこと

- worktree の実体を USB（`/mnt/usb_sd64c/Fakers_Notion/worktrees/`）に移し、`.git-worktree/` からは symlink にした。冷間ビルドとテストは SD 52 分、USB 24 分（[作業記録](../log/work/2026-10-23-s004-usb-worktrees.md)）。

### S005（P2 の 1 回目、2026-10-23）で済んだこと

- リモートの編集でキャレットが末尾へ飛ばないようにした（`session.ffi.mjs` の `applyRemote`。Y.RelativePosition で選択範囲を保つ）。入力欄は `<input>` のまま。contenteditable は複数行やインライン装飾が要るときに回す。
- flush のときに最初の見出しの文字列を `title` 列へ写す。
- E2E にキャレット保持・title 同期・切断中の編集の再接続後の復元を足した。**P2 の完了条件のうち「キャレットが飛ばない」「再接続後に切断中の差分が復元される」を満たした。**

### S006（P2 の 2 回目、2026-10-23）で済んだこと

- `FakersWeb.Presence` で参加者を追い、ページの上部に他の人の名前を色付きで並べた。名前はタブごとの「ゲスト xxxx」（認証は P4）。
- 自分の選択範囲を Y.RelativePosition（base64）で Presence の meta に載せ、他の人の画面では入力欄の上に固定した層へキャレットと選択範囲を描く。サーバは位置の中身を見ず、長さと形だけを検める。
- E2E に Presence とリモートのキャレット（追従・フォーカスを外すと消える・再接続後に参加者が増えない）を足した。

### P2 の残り

- S007: ブロックの種類の追加（リスト・ToDo・コード・引用・区切り・トグル）。
- 日本語入力の変換中にリモート更新が来たときの扱い（今は入力欄の値を書き換えるので変換が切れうる）。
