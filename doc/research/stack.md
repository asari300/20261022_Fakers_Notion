# P1 の技術スタック調査（版・API・落とし穴）

- 確認日: 2026-10-22（S001）。調査は Plan エージェント（Opus、effort medium）が crates.io / hex.pm / npm の API と各ソースを読んで行い、ここに出典つきで写した。
- 【未確認】と書いたものは実装時（S002）に確かめる。

## 版（検証済み）

| 層 | パッケージ | 版 | 出典 |
| --- | --- | --- | --- |
| Rust | yrs | 0.28.0（`features = ["small-client"]`） | <https://crates.io/crates/yrs>、<https://docs.rs/crate/yrs/0.28.0/features> |
| Rust | rustler（crate） | 0.38（0.39.0 は 2026-10-12 に出たが Hex 側が 0.38.0 なので揃える） | <https://crates.io/crates/rustler>、<https://hex.pm/packages/rustler> |
| Elixir | phoenix / phx_new | 1.8.16（2026-10-20） | <https://hex.pm/packages/phx_new> |
| Elixir | ecto_sqlite3 | 0.26.0（ecto / ecto_sql ~> 3.14、exqlite ~> 0.40。exqlite の最新は 0.43.0） | <https://hex.pm/packages/ecto_sqlite3>、<https://github.com/elixir-sqlite/exqlite/blob/v0.43.0/mix.exs> |
| Elixir | rustler（Hex） | 0.38.0 | <https://hex.pm/packages/rustler> |
| Gleam | gleam_stdlib / gleam_json | 1.0.5 / 3.1.0（gleam_json 3.x は Erlang で OTP 27 の `json` モジュールを使う） | <https://hex.pm/packages/gleam_json> |
| Gleam | lustre / lustre_dev_tools / rsvp | 5.7.1 / 2.4.0 / 2.0.0 | <https://hex.pm/packages/lustre>、<https://hex.pm/packages/lustre_dev_tools>、<https://hex.pm/packages/rsvp> |
| Gleam | gleam_otp | 1.0.0（2025-06-12）、1.2.0（2025-10-03）。actor と `gleam/otp/static_supervisor` | <https://www.hex.pm/packages/gleam_otp/1.0.0>、<https://gleam-otp.hexdocs.pm/1.0.0/> |
| npm | yjs / phoenix / esbuild | 13.6.33 / 1.8.16 / 0.28.x | npm registry |
| 道具 | mix_gleam | 0.6.2（2023-11。最後のコード変更 2024-02） | <https://hex.pm/packages/mix_gleam>、<https://github.com/gleam-lang/mix_gleam> |

## 事実と落とし穴

### Rustler

- 0.38 で `rustler::init!` の関数リストが要らなくなり、`resource!` マクロは `#[rustler::resource_impl]` に置き換わった。`#[rustler::nif(schedule = "DirtyCpu")]` は変わらない。MSRV は 1.91（この機械は 1.99.1）。出典: <https://github.com/rusterlium/rustler/blob/master/CHANGELOG.md>、<https://github.com/rusterlium/rustler/blob/rustler-0.38.0/UPGRADE.md>。
- 生成される `ErlNifEntry` は `upgrade: None`（<https://github.com/rusterlium/rustler/blob/rustler-0.38.0/rustler_codegen/src/init.rs>）。erl_nif の文書では、`upgrade` が `NULL` だと古い版が読み込まれたままでは新しい版を読み込めない（<https://github.com/erlang/otp/blob/OTP-27.3/erts/doc/references/erl_nif.md>）。→ NIF モジュールはホットスワップの対象にしない（[ADR-0003](../adr/0003-crdt-yjs-yrs.md)）。
- rustler_mix 0.38.0 の `path:` は `cargo rustc -p <crate> --message-format=json-render-diagnostics` を実行するディレクトリ（既定 `native/<crate>`、相対は Mix プロジェクトのルートから）。成果物は cargo の JSON の `compiler-artifact` から見つけて `priv/native/<crate>.so` にコピーするので、target dir が workspace 共有でも動く。`cargo metadata` で path 依存（`fakers_core`）を `@external_resource` に登録する。`skip_compilation?: true` は cargo を飛ばして `load_from` から読む（リリース用。今は使わない）。出典: <https://github.com/rusterlium/rustler/tree/rustler-0.38.0/rustler_mix/lib>。
- 戻り値 `Result<T, String>` は `{:ok, t} | {:error, msg}` にエンコードされる【未確認: 実装時に確かめる】。バイナリは `OwnedBinary::new(n)` + `copy_from_slice` + `release(env)`（0.39 の `From<&[u8]> for Binary` は 0.38 に無い）。

### yrs 0.28

- 既定の client ID は 53 bit。feature `small-client` が「yrs v0.26 以前と pre-v14 の Yjs との互換のため」にある。npm の yjs の latest は 13.6.33 → `small-client` を有効にする。出典: <https://docs.rs/crate/yrs/0.28.0/features>。
- `Options::offset_kind` の既定は `OffsetKind::Bytes`（UTF-8）。yjs は UTF-16。→ すべての `Doc` を `Doc::with_options(Options { offset_kind: OffsetKind::Utf16, .. })` で作る。出典: <https://docs.rs/yrs/0.28.0/yrs/>。
- 使う API: `TransactionMut::apply_update(&mut self, Update) -> Result<(), UpdateError>`、`Update::decode_v1`、`txn.encode_state_as_update_v1(&StateVector)`、`txn.state_vector().encode_v1()`、自由関数 `merge_updates_v1` / `encode_state_vector_from_update_v1` / `diff_updates_v1`、`MapPrelim` / `ArrayPrelim` / `TextPrelim`、`ToJson::to_json(&txn) -> Any`。
- 【未確認】`MapPrelim` にネストした `TextPrelim` を入れる正確な書き方（`HashMap<Arc<str>, In>` を包む）。
- 依存は中程度（arc-swap、async-lock、async-trait、dashmap、fastrand、serde、serde_json、smallstr、smallvec、thiserror）。default features は無し。

### yjs（クライアント）と WASM の比較

| | (a) yjs（npm） | (b) yrs を WASM に |
| --- | --- | --- |
| RPi でのビルド | Rust のビルド無し。esbuild は数秒 | wasm32 向けに yrs と依存をもう 1 回ビルド。`wasm-bindgen` crate は CLI 0.2.129 と同じ版が要る。wasm-opt は無い |
| 束の大きさ | yjs + lib0 で数十 KB（gzip）【未確認】 | `ywasm` 0.28.0 の npm は展開で 1.23 MB（ほぼ .wasm） |
| Lustre | 同期。`import * as Y from "yjs"` | `init(url)` が非同期。起動を promise の後にする |
| ワイヤ互換 | yrs は同じ lib0 v1 + `small-client` | 同じ実装 |

→ P1 は (a)。(b) は P5（[ADR-0003](../adr/0003-crdt-yjs-yrs.md)）。yjs 13.6.33 の型定義で `encodeStateVectorFromUpdate` と `encodeStateAsUpdate` を確認した（<https://unpkg.com/yjs@13.6.33/dist/src/index.d.ts>）。

### Gleam と Lustre

- Elixir 本体の Gleam サポート（<https://github.com/elixir-lang/elixir/pull/14262>）は未マージ。Elixir Forum のテスター募集（<https://elixirforum.com/t/request-for-testers-gleam-support-in-mix/70166>）。→ mix_gleam も本体サポートも使わず、mix.exs のカスタムコンパイラにする（[ADR-0004](../adr/0004-gleam-integration.md)）。
- Gleam 1.19.2 は `compile-package` と `export erlang-shipment` を持つ（`gleam --help`）。path 依存は依存元のターゲットでコンパイルされる（<https://gleam.run/documentation/gleam-toml-reference>）。
- lustre_dev_tools 2.4.0 のコマンドは `gleam run -m lustre/dev start|build|add`。`build` は `./dist` に書く（`[tools.lustre.build] outdir`、`minify`、`no_html`）。Bun でバンドルする（`bin.bun = "system"` あり）。出典: <https://lustre-dev-tools.hexdocs.pm/index.html>、<https://lustre-dev-tools.hexdocs.pm/toml-reference.html>、<https://lustre-dev-tools.hexdocs.pm/lustre/dev.html>。
- この RPi は `getconf PAGESIZE` = 16384。Bun の aarch64 Linux での非 4K ページ対応は未解決（<https://github.com/oven-sh/bun/issues/17627>）。→ lustre_dev_tools は使わず、npm の esbuild（Go のバイナリ、linux-arm64 あり）でバンドルする。
- Lustre 5.7.1 は `application(init, update, view)` と `start(app, "#app", flags)`、`effect.from(fn(dispatch) {...})`。【未確認】`rsvp.get` と `expect_json` の名前。

### Phoenix 1.8.16

- `mix phx.new` のフラグは 1.8.16 の installer のソースで確認: `--no-assets` は `--no-esbuild` と `--no-tailwind` の両方、`--no-html` は phoenix_html・LiveView・live_reload を外す、`--no-agents-md` で AGENTS.md を作らない。出典: <https://github.com/phoenixframework/phoenix/blob/v1.8.16/installer/lib/mix/tasks/phx.new.ex>、<https://github.com/phoenixframework/phoenix/blob/v1.8.16/installer/lib/phx_new/generator.ex>。
- Channel のバイナリ push・reply・broadcast は `channel.ex` と `v2_json_serializer.ex` で確認: <https://github.com/phoenixframework/phoenix/blob/v1.8.16/lib/phoenix/channel.ex>、<https://github.com/phoenixframework/phoenix/blob/v1.8.16/lib/phoenix/socket/serializers/v2_json_serializer.ex>。
- `--no-html` では `test/support/channel_case.ex` が無いので、`mix phx.gen.channel Document` で作る（`UserSocket` の作成に yes）。
- ecto_sqlite3 の生成は `">= 0.0.0"` なので `"~> 0.26"` に固定する。
- 【未確認】exqlite の aarch64-linux-gnu のプリビルド NIF が取れること。`mix local.rebar --force --if-missing` の存在。

### mise

- プロジェクトの `mise.toml` の `[settings] jobs` が効くか【未確認】（効かなければ `[env] MISE_JOBS = "1"`）。`{{config_root}}` が `dir` で使えるか【未確認】。出典: <https://mise.jdx.dev/tasks/toml-tasks.html>。
- この RPi の mise は 2026.10.15（linux-arm64）。グローバルの版が無く、プロジェクトの `mise.toml` が無いと shim が動かない。`[settings] jobs = 1` はプロジェクトの `mise.toml` で受け付けられた（S001）。
- `activate_aggressive` の既定は false で、PATH にすでにある nvm の node（v24.22.1）が mise の node（24.22.0）より先に出た。`[settings] activate_aggressive = true` で mise のツールが先頭になる（S001 で確認）。
- この RPi の erlang 27.3.4.19（mise）は GLIBC_2.34 までしか要求しない（`strings beam.smp`）。glibc 2.36 で動く。

### 機械

- Raspberry Pi 500（aarch64、Linux 6.12 rpt-rpi-2712、4 コア、RAM 7.9 GiB、16K ページ）。2026-10-22 の時点で空きメモリ 1 GB 未満、ディスクの空き 9.3 GB、Docker 稼働中、Postgres / sqlite3 CLI / just / wasm-pack / wasm-opt は無し。gcc 12.2 と make はある。
- rustup のターゲット: aarch64-unknown-linux-gnu、wasm32-unknown-unknown、wasm32-wasip2、aarch64-linux-android。wasm-bindgen CLI 0.2.129（mise）。
- Playwright の Chromium 1248 は GlobeMode の S017 で入っている（`~/.cache/ms-playwright`）。playwright 1.64.0 に対応。

## S002 で確かめたこと（2026-10-22）

| 項目 | 結果 |
| --- | --- |
| Rustler の `Result<T, String>` | `{:ok, t}` / `{:error, msg}` にエンコードされた |
| exqlite の aarch64-linux-gnu プリビルド | `exqlite-nif-2.17-aarch64-linux-gnu-0.43.0.tar.gz` を取得できた（gcc でのビルドは不要） |
| `rsvp` の関数名 | `get(url, handler)`、`post(url, body, handler)`、`expect_json(decoder, handler)`。`Error(body)` は `BadBody` / `BadUrl` / `HttpError` など |
| mise の `[settings] jobs` | プロジェクトの `mise.toml` で受け付けられた。`mise run test` の `depends` は jobs = 1 で順に走る |
| mix.exs の中の `Mix.Tasks.Compile.*` | `compilers:` で拾われた |
| yrs の `MapPrelim` | `MapPrelim::default()` を `push_back` して `MapRef::insert` で埋める。`TextPrelim::new(text)` を値にできる |
| yjs の束の大きさ | esbuild で 507.6 KB（dev、minify 無し）、`--minify` で 181.7 KB。yjs + lib0 + phoenix + Lustre + gleam_stdlib を含む |
| Phoenix JS のバイナリ payload | `channel.push("update", ArrayBuffer)` と `channel.on("sync", buf => new Uint8Array(buf))` で動いた（E2E） |
| Phoenix の dev の `PORT` | 環境変数 `PORT` でポートを変えられる（E2E は 4100） |
| yrs のビルド時間 | RPi で依存を含めて約 22 s（`-j 2`、debug）。Phoenix の依存の `deps.compile` は約 26 s |
| `mix phx.new --no-html` の `static_paths` | `~w(assets fonts images favicon.ico robots.txt)` が生成されるが `fonts` と `images` は無い。`~w(assets favicon.ico robots.txt)` に直した |
