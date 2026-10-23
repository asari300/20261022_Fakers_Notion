# S006 `presence-cursors`

| | |
| --- | --- |
| 日付 | 2026-10-23 |
| ブランチ | `feature/s006-presence-cursors` |
| worktree | `.git-worktree/s006-presence-cursors`（実体は `/mnt/usb_sd64c/Fakers_Notion/worktrees/s006-presence-cursors`） |
| Phase | P2 |
| セッション文書 | `doc/sessions/S006-presence-cursors/` |
| セッション記録 | `log/sessions/2026-10-22-fdaf1939-ea4d-47eb-856a-abcdf5ffa999.md` |

## 依頼

「進めて。サブエージェントは sonnet / effort high」。S005 の終わりに挙げた次の候補のうち、既定の S006（Presence とリモートのカーソル表示）を進めた。

## 決めたこと

- **カーソルは Phoenix.Presence の meta に載せる**（別イベントの broadcast にしない）。後から入った人にも今のカーソルが届き、切断した人のカーソルは Presence が自動で消すので、後片付けのコードが要らない。（既定のまま進めた）
- **位置は yjs の相対位置を base64 にした文字列で送る**。絶対位置だと、受け手の手元の未送信の編集の分だけずれる。相対位置はキャレットの手前に文字を打っても変わらないので、送信側で同じ値なら送らず、入力のたびの送信が要らない。
- **user_id はサーバが join ごとに振る**（クライアントに名乗らせない）。名前はクライアントが送り、サーバで trim して 32 文字に切る。カーソルの block は 64 バイト、anchor / head は 256 バイトまで。
- **描画は Lustre の外**。`<input>` の中にはキャレットを描けないので、画面に固定した透明な層に、canvas で測った文字幅から x 座標を出して縦線・名前・選択範囲を置く。Lustre の差分描画とぶつからない。
- 色は user_id のハッシュから hsl で決める（全員の画面で同じ人は同じ色）。

## やったこと

- `src/Elixir/fakers/lib/fakers_web/presence.ex`（新規）と `application.ex` の子プロセスに追加。
- `document_channel.ex`: join で user_id を振って返事に入れ、`:after_join` で track と `presence_state` の push。`"cursor"` を検めて `Presence.update`。`%{}` はカーソルを消す。
- `session.ffi.mjs`: `open` に `on_peers` を足し、Presence の同期、自分のカーソルの送信（`selectionchange` ほか。1 フレームに 1 回）、他人のカーソルの描画（文書の更新・スクロール・リサイズで描き直す）、`close` での後片付け。
- `session.gleam` / `fakers_web.gleam`: `Peer` と `PeersChanged`、ナビに参加者を並べる。`app.css` に `.peers` と `.remote-*`。
- テスト: Channel テストに Presence（名前の整形、cursor の載せ替え、長すぎる block の拒否、消去、退室で leaves）。E2E に 5b（参加者 1 人、キャレットの名前と位置、追従、座標が入力欄の中、フォーカスを外すと消える）と、再起動後に参加者が互いに 1 人ずつであること。

## 検証

- `mise run test:elixir`: 21 tests, 0 failures。
- `mise run test:web`: 10 passed。
- `mise run test:e2e`: OK（tab1→tab2 27 ms、切断中の編集が再接続後 4937 ms で届いた）。
- `mise run test`（全部）: Rust 7 passed、interop OK、Gleam 6+6+10 passed、Elixir 21 tests 0 failures、E2E OK（tab1→tab2 50 ms、再接続後 1853 ms）。Elixir は 3 回続けて流して 3 回とも 0 failures。`mix format --check-formatted` と `gleam format --check` も通った。
- `check_docs.py`: 全デッキ OK / リンク 141 件中の切れ 0 件。`render_slides.py`: 問題 0 件（スライドと解説書は Sonnet のサブエージェントが書いた）。
- セッション記録の `--check`: 取りこぼし 0 件。
- スクリーンショットで選択範囲（2〜4 文字目）とキャレット・名前ラベルの位置を目で確かめた（`doc/sessions/S006-presence-cursors/presence.png`）。

## 残したこと

- 名前は「ゲスト xxxx」のまま。名前の変更とアカウントは P4（ワークスペースと権限）で。
- カーソルの x 座標は canvas の文字幅で出すので、合字やカーニングで 1px ほどずれうる。複数行のブロック（contenteditable）にしたら Range の矩形に替える。
- 日本語入力の変換中にリモート更新が来たときの扱いは残ったまま。
