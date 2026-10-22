# このリポジトリでの作業ルール

Fakers Notion は Notion を模倣する共同編集アプリ。コアは Rust、リアルタイムと分散は Elixir / Phoenix、共有する型と UI は Gleam / Lustre。全体像は [README.md](README.md)、設計は [doc/architecture.md](doc/architecture.md)、順序は [doc/roadmap.md](doc/roadmap.md) にある。運用の型は兄弟リポジトリ GlobeMode（`20261018_GlobeMode`）と同じにしてある。

以下は**このリポジトリで作業するとき必ず守ること**。

---

## 1. 作業は git worktree の feature ブランチで行う

`main` の作業ツリーを直接編集しない。作業（＝1セッション）ごとに worktree を切る。手順は `/start-session` スキルにある。

```bash
MAIN=$(git worktree list --porcelain | awk '/^worktree /{print $2; exit}')   # main のチェックアウト
cd "$MAIN"
U=/mnt/usb_sd64c/Fakers_Notion/worktrees   # 実体は USB（SD の容量と書き込み速度のため）
git worktree add -b feature/<topic> $U/<topic> main
ln -s $U/<topic> .git-worktree/<topic>
cd .git-worktree/<topic>
mise trust && mise install --locked   # worktree のパスごとに信頼が要る
uv sync                               # worktree ごとに必須
```

- ブランチ名は `feature/<topic>`。`<topic>` は `sNNN-<英小文字とハイフン>`（例 `s002-vertical-slice`）。
- worktree の**実体は `/mnt/usb_sd64c/Fakers_Notion/worktrees/<topic>`**（USB, ext4）。`.git-worktree/<topic>` はそこへの symlink（`.gitignore` 済み）。計測（S004）では冷間ビルドが SD の 52 分に対し USB 24 分、書き込みは 3 → 53 MB/s。`git worktree move` はデバイスをまたげないので、移すときは作り直す。
- **orca が作る worktree**（`~/orca/workspaces/<repo>/<名前>`、ブランチ `asari300/<名前>`）は**セッションの起動場所にすぎない**。そこでは何も編集もコミットもしない。作業はこの規約の worktree で行う。
- **`.venv` を worktree 間で共有・symlink しない。** editable install はそのチェックアウトの `src/` を指すため。
- コミットは feature ブランチに行う。
- **main は直接 push する**（GlobeMode と同じ運用。PR は使わない）。
  - 手順: 検査を通した feature ブランチを main に `--no-ff` でマージし、`git push origin main` する（`/finish-session` の 6）。
  - feature ブランチ自体は push しない。
  - CI は `.github/workflows/ci.yml`（[ADR-0006](doc/adr/0006-license-and-ci.md)）。push したら `gh run watch` で結果を確かめる。
  - push が通ったら（CI ができたら CI が成功したら）、最新から数えて 2 つ以上前の worktree を片付ける（`/finish-session` の 7）。
- main に未コミットの変更があったら、そこで止めてユーザーに伝える。勝手にコミットも stash もしない。

---

## 2. ディレクトリ構造の意味

| 場所 | 意味 | 編集してよいか |
| --- | --- | --- |
| `src/Rust/` | Cargo workspace。`crates/fakers_core`（純 Rust の文書モデルと CRDT）、`crates/fakers_nif`（Rustler の薄い皮） | ○ |
| `src/Elixir/fakers/` | Phoenix アプリ（Channel、文書ごとのプロセス、Ecto / SQLite）。**業務ロジックの計算は Rust 側に置く** | ○ |
| `src/Gleam/fakers_shared/` | Erlang と JavaScript の両ターゲットで共有する型（ブロック、ページ）。**FFI を置かない** | ○ |
| `src/Gleam/fakers_web/` | Lustre の SPA（JavaScript ターゲット）。yjs と Phoenix の JS は FFI の中だけで触る | ○ |
| `src/Python/mod/` | Python パッケージ `fakers_notion`（ツール用途。製品のロジックを置かない） | ○ |
| `src/Python/e2e/` | Playwright の E2E（`mise run test:e2e`。Phoenix を PORT=4100 で起動する） | ○ |
| `doc/architecture.md` `roadmap.md` `features.md` | **正典**。計画を変えたら同じコミットで直す | ○ |
| `doc/adr/` | 設計判断の記録。覆すときは消さずに Superseded にする | ○（追記） |
| `doc/research/` | 調査の記録。事実ごとに URL と確認日を付ける | ○ |
| `doc/sessions/SNNN-<topic>/` | セッションごとのスライドと解説書 | ○（そのセッションの間だけ） |
| `doc/assets/` | スライドの共通 CSS と JS | ○ |
| `log/work/` | 作業記録（手動、1セッション1枚） | ○ |
| `log/sessions/` | 伏せ字にしたセッション記録（コミットする） | ×（finish-session がコピーする） |
| `log/local/` | フックの出力。生ログを含む | ×（**コミットしない**） |

- 検査はまとめて `mise run test`（Rust の fmt / clippy / test、yrs ⇄ yjs の相互運用、Gleam の両ターゲットのテスト、Elixir の `mix test`、2 タブの E2E）と `mise run docs:check`（スライドとリンク、Playwright）で回す。開発サーバは `mise run dev`（SPA を束ねてから `mix phx.server`）。
- **言語の管理は uv・cargo・mise で分担する**（[ADR-0001](doc/adr/0001-toolchain.md)）。

  | 道具 | 受け持つもの | ロックファイル |
  | --- | --- | --- |
  | uv | Python 本体（`.python-version`）と Python の依存 | `uv.lock` |
  | cargo / rustup | Rust の依存と workspace。版は rustup の stable | `Cargo.lock` |
  | mise | それ以外のツールの版（erlang / elixir / gleam / node、uv 本体）とタスク（`mise run …`） | `mise.lock` |

  - `rust-toolchain.toml` は作らない。Python を mise に入れない。
  - ロックファイルはすべてコミットする。
- 機械は Raspberry Pi 500（aarch64、4 コア、RAM 8 GB、16K ページのカーネル）。重いビルドの前に `free -h` を見る。Cargo の target は `src/Rust/target/` に 1 つ。同じ worktree で cargo を 2 つ同時に走らせない。

---

## 3. 文書の書き方

- 文書は日本語で書く。README は英語の要約を付ける。
- 調査した事実には出典 URL と確認日を付ける。確認できなかったものには【未確認】と書く。推測を事実のように書かない。
- 設計の判断は ADR（`doc/adr/NNNN-*.md`、章は「状態 / 背景 / 決定 / 結果」）に書く。正典の文書からリンクする。
- Markdown は markdownlint の警告を出さない。見出し・リスト・表・コードブロックの前後は空行にする。

---

## 4. セッションごとにスライドと解説書を作る

毎セッション `doc/sessions/SNNN-<topic>/` に次の2つを作る。書き方は `/session-docs` スキルにある。

| ファイル | 内容 |
| --- | --- |
| `slides.html` | HTML スライド。`../../assets/slides.css` と `slides.js` だけを使う。**外部 CDN・`<style>`・`style=` を使わない**（オフラインで開けるように） |
| `解説書.md` | Markdown の解説書。章立ては「目的 / 決定と理由 / 図 / 再現手順 / 次回」。正典の文書へリンクする |

索引は [doc/sessions/README.md](doc/sessions/README.md)。S 番号・日付・ブランチ・セッション ID・成果物を1行ずつ足す。

---

## 5. ログはすべて残す（公開用は伏せ字）

### セッション記録（自動）

`.claude/settings.json` の `Stop` / `SessionEnd` フックが [.claude/hooks/save_session_log.py](.claude/hooks/save_session_log.py) を呼ぶ。

```text
log/local/<日付>-<セッションID>.md           整形版（伏せ字済み）   … コミットしない
log/local/raw/<日付>-<セッションID>.jsonl.gz 完全な生ログ（伏せ字なし）… 絶対にコミットしない
log/sessions/<日付>-<セッションID>.md        finish-session がコピーした公開用 … コミットする
```

- 伏せ字にするもの: メールアドレス、ローカルのユーザー名とホームのパス、トークンらしき文字列。
- コピーした後に `python3 .claude/hooks/save_session_log.py --check log/sessions/*.md` が取りこぼし 0 件であることを確かめてからコミットする。
- フックは**セッションを起動したチェックアウト**（`CLAUDE_PROJECT_DIR`）の `log/local/` に書く。orca の worktree から起動したセッションでは、そこの `log/local/`（git 管理外）に溜まる。finish-session はどちらの場合も `--latest --match <ブランチ名>` で取り出して worktree の `log/sessions/` にコピーする。

### 作業記録（手動・1セッション1枚）

`log/work/<日付>-<topic>.md` を [log/work/_TEMPLATE.md](log/work/_TEMPLATE.md) から作る。セッション記録は「何が起きたか」の全量、作業記録は「何を決めたか」を残す。

---

## 6. 締めのチェックリスト

`/finish-session` スキルの手順に従う。**どれかが落ちたらそこで止めて報告する。**

1. コードを触ったら: `mise run test`（Rust / 相互運用 / Gleam / Elixir / E2E）。触った層だけ `mise run test:rust` のように絞ってもよいが、コミットの前には全部回す
2. スライドと解説書がある。`check_docs.py`（外部参照・`<style>`・`style=` が 0 件）と、Playwright の `render_slides.py`（ブラウザでの表示）を通す
3. `doc/` と `log/` の相対リンク切れが 0 件
4. セッション記録をコピーし、`--check` で取りこぼしが 0 件
5. ステージした差分に、メールアドレス・ホームのパス・トークンが 0 件（`pyproject.toml` の著者のメールアドレスは意図したもの）
6. 作業記録を数字で仕上げてから、feature ブランチにコミットする
7. main に `--no-ff` でマージし、`git push origin main` する（CI ができたら結果を `gh run watch` で確かめる）
8. push が通ったら（CI ができたら CI が成功したら）、最新から数えて 2 つ以上前の worktree を片付ける（未コミットの変更が無く、main に取り込み済みのものだけ。`git worktree remove` と `git branch -d`）
