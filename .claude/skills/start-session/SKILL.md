---
name: start-session
description: Fakers Notion で新しいセッション（作業）を始める。S 番号を決め、git worktree に feature ブランチを切って mise install と uv sync をし、doc/sessions/SNNN-<topic>/ のスライドと解説書の雛形、作業記録の下書きを作る。「作業を始める」「次のセッション」「worktree を切って」と言われたとき、またはこのリポジトリで実装・修正・文書作成を始める前に使う。
---

# セッションの開始

このリポジトリでは **`main` の作業ツリーを直接編集しない**。理由は [CLAUDE.md](../../../CLAUDE.md) の「1. 作業は git worktree の feature ブランチで行う」。

orca が作った worktree（`~/orca/workspaces/<repo>/<名前>`、ブランチ `asari300/<名前>`）から起動したセッションでも同じ。そこは起動場所にすぎないので、規約の worktree を切ってそちらで作業する。

## 1. S 番号と topic を決める

- S 番号は [doc/sessions/README.md](../../../doc/sessions/README.md) の索引の最後の番号に 1 を足したもの（3 桁、例 `S002`）。
- topic は英小文字とハイフンで、何をするかがわかる短い名前（例 `vertical-slice`）。
  - ユーザーの依頼から自分で決めてよい。迷うときだけ確認する。
- ブランチは `feature/sNNN-<topic>`、worktree は `.git-worktree/sNNN-<topic>`。
- どの Phase の作業かを [doc/roadmap.md](../../../doc/roadmap.md) で確かめる。

## 2. worktree を作る

```bash
MAIN=$(git worktree list --porcelain | awk '/^worktree /{print $2; exit}')
TOPIC=sNNN-<topic>
WT="/mnt/usb_sd64c/Fakers_Notion/worktrees/$TOPIC"   # 実体は USB。$MAIN/.git-worktree/$TOPIC は symlink

cd "$MAIN"
git worktree list                      # 同名が無いか確認
git status --porcelain                 # main 側に未コミットの変更が無いか確認
git worktree add -b "feature/$TOPIC" "$WT" main
ln -s "$WT" "$MAIN/.git-worktree/$TOPIC"
cd "$WT" && mise trust && mise install --locked && uv sync
```

- `main` に未コミットの変更（未追跡ファイルを含む）があったら、**そこで止めてユーザーに伝える**。勝手にコミットも stash もしない。
- `.venv` を main からコピー・symlink しない。
- Rust の target（`src/Rust/target/`）は worktree ごとに作られる。前の worktree の target を `cp -a` でコピーすると依存のビルドを省ける（レジストリの依存は worktree のパスに依らない。コピー中は cargo を走らせない）。

## 3. セッション文書の雛形を作る

```bash
mkdir -p "doc/sessions/SNNN-<topic>"
cp doc/sessions/_template/slides.html "doc/sessions/SNNN-<topic>/slides.html"
cp doc/sessions/_template/解説書.md   "doc/sessions/SNNN-<topic>/解説書.md"
```

- タイトルと日付を書き換える。中身はセッションの終わりに `/session-docs` の手順で書く。
- [doc/sessions/README.md](../../../doc/sessions/README.md) の索引に行を足す。状態は「作業中」にする。

## 4. 作業記録の下書きを作る

`log/work/<YYYY-MM-DD>-sNNN-<topic>.md` を [log/work/_TEMPLATE.md](../../../log/work/_TEMPLATE.md) から作る。

- この時点では「日付 / ブランチ / worktree / Phase / 依頼」まで埋める。
- 残りは作業しながら書き足す。

## 5. 以降は worktree の中で作業する

- すべてのコマンドとファイル編集を `$WT` 側で行う。
- 最初のファイル操作のときに、`$MAIN` や orca の worktree のパスを使っていないか一度確かめる。
- シェルのカレントディレクトリが起動場所に戻る環境では、**絶対パスで `$WT` を指す**。

## 終わったら

`/finish-session` を使う（検査 → 文書 → セッション記録 → 作業記録 → コミット → マージと push）。
