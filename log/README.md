# log — 作業とセッションの記録

このリポジトリでの作業は**すべて記録を残す**。方針は [../CLAUDE.md](../CLAUDE.md) の「6. ログはすべて残す（公開用は伏せ字）」。

```text
log/
├── local/                          フックの出力（git 管理外）
│   ├── <日付>-<セッションID>.md      整形版（伏せ字済み）
│   └── raw/<日付>-<セッションID>.jsonl.gz  完全な生ログ（伏せ字なし。絶対にコミットしない）
├── sessions/                       公開用のセッション記録（コミットする）
│   └── <日付>-<セッションID>.md      finish-session が local/ からコピーしたもの
└── work/                           作業記録（手動。1セッション1枚）
    ├── _TEMPLATE.md
    └── <日付>-sNNN-<topic>.md
```

## local/ — 自動、コミットしない

- `.claude/settings.json` の `Stop` / `SessionEnd` フックが [../.claude/hooks/save_session_log.py](../.claude/hooks/save_session_log.py) を呼んで書き出す。
- 毎ターン上書きされるので、セッションが途中で落ちても直前までが残る。
- `raw/*.jsonl.gz` が**完全な記録**。`gunzip -c <file> | jq` で全文を辿れる。中身にはメールアドレスやローカルのパスがそのまま入っている。

## sessions/ — 公開用、コミットする

- `/finish-session` が `local/` の整形版をここにコピーする。
- コミットの前に、`python3 .claude/hooks/save_session_log.py --check log/sessions/*.md` で伏せ字の取りこぼしが 0 件であることを確かめる。
- 伏せ字にするもの: メールアドレス、ローカルのユーザー名とホームのパス、トークンらしき文字列。
- 取りこぼしが見つかったら、フックの `REDACTIONS` に規則を足して作り直す。手で直さない。

## work/ — 手動

- セッション記録が「何が起きたか」の全量なのに対して、こちらは**「何を決めたか」**を残す。
- 1セッション（＝1つの feature ブランチ）につき1枚。雛形は [work/_TEMPLATE.md](work/_TEMPLATE.md)。
