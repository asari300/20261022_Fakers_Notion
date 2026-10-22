# S002 `vertical-slice`

| | |
| --- | --- |
| 日付 | 2026-10-22 |
| ブランチ | `feature/s002-vertical-slice` |
| worktree | `.git-worktree/s002-vertical-slice` |
| Phase | P1（骨組みと最初の縦スライス） |
| セッション文書 | `doc/sessions/S002-vertical-slice/` |
| セッション記録 | [log/sessions/2026-10-22-fdaf1939-ea4d-47eb-856a-abcdf5ffa999.md](../sessions/2026-10-22-fdaf1939-ea4d-47eb-856a-abcdf5ffa999.md)（S001 と同じセッション） |

## 依頼

S001 で承認されたプラン（[roadmap.md](../../doc/roadmap.md) の「S002 の計画」12 段）を実装する。完了時の姿: `mise run test` が 3 言語とも通り、`mise run dev` で 2 つのタブの編集が即時反映され、再起動しても残る。

## 決めたこと

- **相互運用ゲートは両方向**（既定のまま）: `src/Gleam/fakers_web/test/interop.mjs` が `cargo run --example dump_page` の状態を yjs に適用し、yjs の編集を `cargo run --example apply_hex` で yrs に戻す。絵文字（UTF-16 で 2 単位）も入れる。これが通ったので [ADR-0003](../../doc/adr/0003-crdt-yjs-yrs.md) を Accepted にした。
- **SPA はサブエージェント**（既定のまま、ユーザーの方針 Opus / effort medium）: 契約（`[{"id","type","text"}]`、`"sync"` / `"update"` のバイナリ、FFI の API、CSS のクラス名）を渡して `src/Gleam/fakers_web/` だけを編集させた。約 3 分、ツール呼び出し 12 回。返ってきた差分: Enter は `event.advanced` で `isComposing` を見る、`diff_text` はサロゲートペアを切らない、未接続中の変更は次の `sync` の追いつきで送る、`focus_block` で新ブロックにフォーカス。
- **E2E は Python の Playwright で自動化**（既定のまま）: `src/Python/e2e/two_tabs.py`。Phoenix を PORT=4100 で起動し、作成 → 2 タブ目 → 入力の反映 → Enter → 種別 → 再起動 → リロードを確かめる。`mise run test` に入れた。
- **`static_paths` から `fonts` と `images` を外した**（既定のまま）: `phx.new --no-assets` が作る `~w(assets fonts images favicon.ico robots.txt)` のうち 2 つはディレクトリが無く、dev の `raise_on_missing_only` で落ちるため。
- **Phoenix の生成物**: `assets/js/user_socket.js`（`phx.gen.channel` が作る）は使わないので消した。生成された `DocumentChannel` と `UserSocket` は書き直した。
- **`DocumentServer` の flush は落とさない**（既定のまま）: `Repo.update_all` の失敗は `rescue` してログに書き、次の flush か停止でもう一度試す。テストの sandbox が閉じた後の停止でプロセスが落ちないように。
- **clippy**: `s.len() % 2 != 0` を `!s.len().is_multiple_of(2)` に直した（rustc 1.99 の `manual_is_multiple_of`）。

## やったこと

- `mise.toml`: `setup`、`test:rust` / `test:interop` / `test:shared` / `test:web` / `test:elixir` / `test:e2e` / `test`、`build:web` / `build:elixir` / `build`、`dev`。
- `src/Rust/`: workspace（resolver 3、edition 2024、`.cargo/config.toml` で jobs = 2）、`crates/fakers_core`（`new_page` / `apply_update` / `state_vector` / `diff` / `blocks_json` / `edit_text`、`to_hex` / `from_hex`、テスト 7 本、例題 `dump_page` と `apply_hex`）、`crates/fakers_nif`（Rustler 0.38、cdylib、全部 DirtyCpu）。
- `src/Gleam/fakers_shared/`: `block.gleam`（Block / BlockKind とデコーダ・エンコーダ）、`page.gleam`（PageSummary）、テスト 6 本。
- `src/Gleam/fakers_web/`: `package.json`（yjs 13.6.33、phoenix 1.8.16、esbuild 0.28.2）、`gleam.toml`（lustre 5.7.1、rsvp 2.0.0、fakers_shared の path 依存）、SPA（`fakers_web.gleam`、`session.gleam` + `session.ffi.mjs`、`route.gleam` + `route.ffi.mjs`、`api.gleam`）、`app.css`、`entry.mjs`、テスト 10 本、`test/interop.mjs`。
- `src/Elixir/fakers/`: `mix phx.new`（1.8.16、sqlite3、binary-id、HTML / LiveView / assets / mailer / gettext / dashboard 無し）、`mix.exs`（`Mix.Tasks.Compile.GleamShared`、`ecto_sqlite3 ~> 0.26`、`rustler ~> 0.38.0`）、`Fakers.Native`、`Fakers.Documents` と `Document`（schema、migration）、`DocumentServer`、`Application`（Registry、DynamicSupervisor）、`UserSocket`、`DocumentChannel`、`PageApiController`、`PageController`、`router.ex`、`endpoint.ex`（socket）、`priv/static/index.html`、config（`flush_ms` / `idle_ms`、`reloadable_compilers`）、テスト 19 本。
- `src/Python/e2e/two_tabs.py`。
- 文書: ADR-0003 と 0004 を Accepted に（確かめたことを追記）、`roadmap.md`（S002 で済んだこと）、`architecture.md`（v1。クライアントの構成、検査基盤）、`features.md`（P1 の項目を済に）、`research/stack.md`（S002 で確かめたこと）、`README.md`、`CLAUDE.md`（`src/Python/e2e`、`mise run test` の中身）。
- ユーザー全体: `mix archive.install hex phx_new 1.8.16`、`mix local.rebar`。

## 検証

数字で書く。通っていない項目は「通っていない」と書く。

- `mise run test`（全部、順に）: 全部通過、40.5 s（ビルド済みの状態。E2E のサーバ起動 2 回を含む）。
  - `test:rust`: fmt の差分 0、clippy 0 件、テスト 7 本通過。yrs の初回ビルド約 22 s（`-j 2`、debug）。
  - `test:interop`: OK（yrs → yjs のブロック 2 つが一致、yjs → yrs の文字 "hello 😀!"、update 29 バイト、yjs の clientID は 32 bit）。
  - `test:shared`: 6 本 × 2 ターゲット通過。`test:web`: 10 本通過。
  - `test:elixir`: 19 本通過、0 失敗（NIF 4、Documents 6、Channel 4、API 3、error_json 2）。
  - `test:e2e`: OK。タブ 1 → タブ 2 の反映 5 ms、Enter と種別の反映、再起動後に 3 ブロックが残った（単独実行で 19.3 s）。
- ビルドの大きさ: `app.js` 507.6 KB（dev）、`fakers_nif.so` 8.8 MB（debug）。exqlite は aarch64 のプリビルド NIF を取得（gcc でのビルド無し）。`mix deps.compile` 約 26 s。
- `check_docs.py`: デッキ 3 件 OK（S001、S002、雛形）/ 文書 26 件・相対リンク 109 件・切れ 0 件。
- `render_slides.py`: デッキ 3 件（S001 7 枚、S002 7 枚、雛形 6 枚）× 3 表示で問題 0 件。16.7 s。
- セッション記録の `--check`: 検査 2 件 / 取りこぼし 0 件（S001 と同じセッションの記録を、この時点の写しで上書きした）。
- ステージした差分の漏洩検査: 0 件。

## 残したこと

- P1 の残り: CI（GitHub Actions）とライセンス（S003 の候補）。
- 切断と再接続の回復は実装した（`sync` の後に state vector で差分を送る）が、E2E では検証していない（P2）。
- controlled input のキャレットの制限（P2 で contenteditable）。見出しブロックと `title` 列の同期（P2）。
- `build:web` の prod 向け `--minify`（182 KB）は未設定。Hex の rustler が 0.39 になったら crate と揃える。
- `DocumentServer` の idle 停止直後の呼び出しの競合は未検証（`ensure_server` で起動し直す設計）。
- GlobeMode の S017 の判断「RPi では elixir が入らない」は、この RPi では当てはまらなかった（S001 の作業記録）。
