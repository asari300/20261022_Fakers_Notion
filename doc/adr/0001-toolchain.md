# ADR-0001 ツールチェーン（uv・cargo / rustup・mise の分担）

- 状態: **Accepted**（2026-10-22、S001）。

## 背景

- 言語が多い（Rust / Elixir / Gleam / Python、UI のバンドルに Node）ので、ツールの版をそろえる仕組みが要る。
- ユーザーの方針（2026-10-22）: 「Python は uv、Rust は Cargo、それ以外は mise で管理」。兄弟リポジトリ GlobeMode の ADR-0003 と同じ型で、違いは Rust を mise ではなく rustup に任せること。
- 機械は Raspberry Pi 500（aarch64）。mise にはすでに erlang 27.3.4.19 / elixir 1.18.3-otp-27 / gleam 1.19.2 / node 24.22.0 が入っているが、グローバルの版が無いので shim は動かない（`No version is set for shim: mix`）。プロジェクトの `mise.toml` が必須。

## 決定

**言語の管理は uv・cargo / rustup・mise の3つで分担する。**

| 道具 | 受け持つもの | ロックファイル |
| --- | --- | --- |
| **uv** | Python 本体（`.python-version`）と Python の依存（ツール用途のみ） | `uv.lock` |
| **cargo / rustup** | Rust の依存と workspace。版は rustup の stable | `Cargo.lock` |
| **mise** | それ以外のツールの版: erlang、elixir、gleam、node、uv 本体。タスク（`mise run …`） | `mise.lock` |

- `rust-toolchain.toml` は作らない。mise にも rust を書かない。
- Python を mise に入れない。
- `mise.toml` の `[settings] jobs = 1`（RPi で並列インストールがメモリを食わないように）、`[env] CARGO_BUILD_JOBS = "2"`。
- 新しい worktree では `mise trust` と `mise install --locked` を実行してから `uv sync` する（start-session スキル）。
- ロックファイルはすべてコミットする。

## 結果

- この RPi の erlang 27.3.4.19 は GLIBC_2.34 までしか要求せず、glibc 2.36 で動く（`mise exec erlang@27.3.4.19 elixir@1.18.3-otp-27 -- mix hex.info` が Elixir 1.18.3 / OTP 27.3.4.19 を返した。2026-10-22）。GlobeMode の S017 で「erlang の arm64 ビルドが glibc 2.38 を要求する」とされた問題は、このインストールでは起きていない。`MISE_DISABLE_TOOLS=elixir` は要らない。
- Phoenix の `phx_new` アーカイブは未インストール。S002 の最初に `mix archive.install hex phx_new 1.8.16` を実行する（ユーザー全体のアーカイブ）。
- Hex 2.5.4 は mise の elixir に入っている。rebar3 は mix が取得する。
