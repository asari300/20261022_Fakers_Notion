# Fakers Notion

**A Notion-like collaborative editor, built with Rust, Elixir and Gleam.**

- **Rust** owns the core: the block document model and the CRDT (yrs), exposed to the BEAM as pure-function NIFs.
- **Elixir / Phoenix** owns real-time and distribution: Channels, one supervised process per open document, PubSub, persistence through Ecto (SQLite for now).
- **Gleam** owns the typed domain model shared by server (Erlang target) and client (JavaScript target), and the single-page UI built with Lustre.
- **Python** is tooling only.

> **Status:** P0 (operating base) done in S001. P1 (skeleton and the first vertical slice: create a page, edit blocks, see edits in another tab in real time, survive a restart) starts in S002. See [doc/roadmap.md](doc/roadmap.md).

Development machine: Raspberry Pi 500 (aarch64). Toolchains: Python via uv, Rust via Cargo / rustup, everything else via mise.

---

## 日本語

Fakers Notion は Notion を模倣する共同編集アプリ。コアは Rust（ブロック文書モデルと CRDT の yrs。BEAM には純関数の NIF として見せる）、リアルタイムと分散は Elixir / Phoenix（Channel、文書ごとの監視されたプロセス、PubSub、Ecto と SQLite）、共有する型と UI は Gleam（Erlang と JavaScript の両ターゲット、Lustre の SPA）。Python はツール用途のみ。

S001 で P0（運用基盤）を済ませた。S002 から P1（骨組みと最初の縦スライス: ページを作り、ブロックを編集し、別のタブに即時反映され、再起動しても残る）に入る。

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
```

ライセンスは未定（[roadmap.md](doc/roadmap.md) の P1 で決める）。
