# Fakers Notion

**A Notion-like collaborative editor, built with Rust, Elixir and Gleam.**

- **Rust** owns the core: the block document model and the CRDT (yrs), exposed to the BEAM as pure-function NIFs.
- **Elixir / Phoenix** owns real-time and distribution: Channels, one supervised process per open document, PubSub, persistence through Ecto (SQLite for now).
- **Gleam** owns the typed domain model shared by server (Erlang target) and client (JavaScript target), and the single-page UI built with Lustre.
- **Python** is tooling only.

> **Status:** P0 (operating base) done in S001. In S002 the first vertical slice works end to end: create a page, edit heading and paragraph blocks in a Lustre SPA, see edits in another tab in about 5 ms over a Phoenix Channel (yjs on the client, yrs in Rust on the server, merged through a Rustler NIF), and keep the content across a server restart (SQLite). `mise run test` runs Rust, Gleam (both targets), Elixir and a two-tab Playwright E2E. Remaining for P1: CI and the license. See [doc/roadmap.md](doc/roadmap.md).

Development machine: Raspberry Pi 500 (aarch64). Toolchains: Python via uv, Rust via Cargo / rustup, everything else via mise.

---

## 日本語

Fakers Notion は Notion を模倣する共同編集アプリ。コアは Rust（ブロック文書モデルと CRDT の yrs。BEAM には純関数の NIF として見せる）、リアルタイムと分散は Elixir / Phoenix（Channel、文書ごとの監視されたプロセス、PubSub、Ecto と SQLite）、共有する型と UI は Gleam（Erlang と JavaScript の両ターゲット、Lustre の SPA）。Python はツール用途のみ。

S001 で P0（運用基盤）を済ませ、S002 で P1 の縦スライスが端から端まで通った: ページを作り、Lustre の SPA で見出しと段落を編集すると、Phoenix Channel 経由で別のタブに約 5 ms で反映され（クライアントは yjs、サーバは Rust の yrs を Rustler の NIF で）、サーバを再起動しても SQLite から復元される。`mise run test` で Rust・Gleam（両ターゲット）・Elixir・2 タブの E2E を回せる。P1 の残りは CI とライセンス。

| 文書 | 内容 |
| --- | --- |
| [doc/features.md](doc/features.md) | Notion を参考に整理した、必要な機能の一覧と Phase |
| [doc/architecture.md](doc/architecture.md) | 層の分担、ディレクトリ、データの流れ、ブロックモデル、プロセス設計 |
| [doc/roadmap.md](doc/roadmap.md) | P0〜P6 と各段階の完了条件 |
| [doc/adr/](doc/adr/) | 設計判断の記録 |
| [doc/research/](doc/research/) | 調査の記録（出典 URL と確認日つき） |
| [doc/sessions/](doc/sessions/) | セッションごとの HTML スライドと解説書 |
| [log/](log/) | 作業記録とセッション記録 |
| [CLAUDE.md](CLAUDE.md) | このリポジトリでの作業ルール |

## はじめかた

```bash
git clone https://github.com/asari300/20261022_Fakers_Notion.git
cd 20261022_Fakers_Notion
mise trust && mise install --locked      # erlang / elixir / gleam / node / uv
uv sync                                  # Python（Playwright は文書の検査に使う）
mise run doctor                          # 版の確認
mise run docs:check                      # スライドとリンクの検査
mise run setup                           # cargo fetch、npm ci、gleam deps download、mix deps.get
mise run test                            # Rust / Gleam / Elixir / 2 タブの E2E
mise run dev                             # SPA を束ねて http://localhost:4000
```

ライセンスは未定（[roadmap.md](doc/roadmap.md) の P1 で決める）。
