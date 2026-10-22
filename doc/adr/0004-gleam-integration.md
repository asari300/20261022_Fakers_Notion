# ADR-0004 Gleam は mix.exs のカスタムコンパイラで組み込み、UI は Lustre + esbuild

- 状態: **Proposed**（2026-10-22、S001）。S002 で Rust → Erlang → Gleam のデコードテストと Lustre の 2 タブ同期が通ったら Accepted にする。

## 背景

- Elixir から Gleam のモジュールを呼ぶ道は 3 つ: mix_gleam（Mix の中で Gleam をコンパイル）、Gleam を別にビルドして path 依存にする、Elixir 本体の Gleam サポート。
- mix_gleam は 0.6.2（2023-11）で止まっていて、最後のコードの変更は 2024-02。Elixir 本体の Gleam サポート（elixir-lang/elixir PR #14262）は未マージで、Elixir 1.18 には入っていない。
- Lustre の開発ツール lustre_dev_tools 2.x は Bun でバンドルする。この RPi のカーネルは 16K ページで、Bun の aarch64 Linux での非 4K ページ対応は未解決の issue がある（oven-sh/bun#17627）。
- Gleam のパッケージは `gleam.toml` の `target` でターゲットを決め、path 依存は依存元のターゲットでコンパイルされる。
- 出典と確認日は [research/stack.md](../research/stack.md)。

## 決定

1. **mix_gleam を使わない。** `src/Elixir/fakers/mix.exs` に約 20 行の `Mix.Tasks.Compile.GleamShared` を定義し、`src/Gleam/fakers_shared` で `gleam build --target erlang` を実行して `build/dev/erlang/*/ebin` を `Code.prepend_path/1` する。`compilers: [:gleam_shared] ++ Mix.compilers()`。Elixir からは `:fakers_shared@block.decode_blocks(json)` のように呼ぶ。
   - `config/dev.exs` に `reloadable_compilers: [:elixir, :app]` を書き、リクエストごとに gleam が走らないようにする。
   - mix.exs の中で定義した `Mix.Tasks.Compile.*` が拾われなければ、`compile: ["gleam_shared", "compile"]` のエイリアスにする。
   - リリースでは `gleam export erlang-shipment` の結果を同梱する（P5）。
2. **`fakers_shared` は `target = "erlang"`、依存は gleam_stdlib と gleam_json だけ、FFI を置かない。** `gleam test` と `gleam test --target javascript` の両方を通す。`fakers_web` は `target = "javascript"` で、`fakers_shared = { path = "../fakers_shared" }`。
3. **UI は Lustre 5.7.1。バンドルは npm の esbuild。lustre_dev_tools は使わない。** パイプラインは `gleam build --target javascript` → `npx esbuild entry.mjs --bundle --format=esm --outfile=../../Elixir/fakers/priv/static/assets/app.js`。`node_modules`（yjs、phoenix、esbuild）は `src/Gleam/fakers_web/` に置く。
4. **Phoenix は生成済みの `Plug.Static` で `/assets/app.js` を配信し、コミットした `priv/static/index.html` を catch-all ルート（`/api` の後ろの `get "/*path"`）から `send_file` で返す。** Phoenix のアセットパイプライン（esbuild / tailwind の Hex パッケージ）は使わない（`mix phx.new --no-assets`）。
5. yjs と Phoenix の JS は `session.ffi.mjs` の中だけで触る。Gleam 側にはブロックの JSON とページの JSON だけを渡す。

## 結果

- Phoenix の `mix phx.new` のフラグ: `--database sqlite3 --binary-id --no-html --no-live --no-assets --no-mailer --no-gettext --no-dashboard --no-agents-md --no-install`。
- 自動リビルド（`watchers:`）は任意。`fs.watch` → gleam build → esbuild の小さな node スクリプトで足せる（S002 の最後）。
- lustre_dev_tools を使いたくなったら、まず 16K ページで Bun が動くか試す。
