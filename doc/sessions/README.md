# セッションの索引

各セッションのスライドと解説書。書き方は `.claude/skills/session-docs/SKILL.md`、雛形は [_template/](_template/)。

| S | 日付 | Phase | 題名 | ブランチ | 状態 | スライド | 解説書 | セッション記録 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| S001 | 2026-10-22 | P0 | 運用基盤と計画: CLAUDE.md、スキル、セッション記録のフック、正典の文書と ADR、P1 の計画 | `feature/s001-ops-and-plan` | 完了 | [slides](S001-ops-and-plan/slides.html) | [解説書](S001-ops-and-plan/解説書.md) | [log](../../log/sessions/2026-10-22-fdaf1939-ea4d-47eb-856a-abcdf5ffa999.md) |
| S002 | 2026-10-22 | P1 | 骨組みと最初の縦スライス: Rust workspace（fakers_core / fakers_nif）、Gleam（fakers_shared / fakers_web）、Phoenix（fakers）、ページの作成・編集・リアルタイム同期（タブ間 約 5 ms）・SQLite への永続化、2 タブの E2E。相互運用ゲート（yrs ⇄ yjs）が通り ADR-0003・0004 を Accepted に | `feature/s002-vertical-slice` | 完了 | [slides](S002-vertical-slice/slides.html) | [解説書](S002-vertical-slice/解説書.md) | [log](../../log/sessions/2026-10-22-fdaf1939-ea4d-47eb-856a-abcdf5ffa999.md)（S001 と同じセッション） |
| S003 | 2026-10-22 | P1 | ライセンスを MIT OR Apache-2.0 に決め、GitHub Actions の CI を足した（ADR-0006） | `feature/s003-ci-license` | 完了 | [slides](S003-ci-license/slides.html) | [解説書](S003-ci-license/解説書.md) | [log](../../log/sessions/2026-10-22-fdaf1939-ea4d-47eb-856a-abcdf5ffa999.md)（S001・S002 と同じセッション） |
| S004 | 2026-10-23 | 運用 | worktree の実体を USB に移し、SD と速度を比べた（冷間ビルド 52 分 → 24 分） | `feature/s004-usb-bench` | 完了 | — | [作業記録](../../log/work/2026-10-23-s004-usb-worktrees.md) | [log](../../log/sessions/2026-10-22-fdaf1939-ea4d-47eb-856a-abcdf5ffa999.md)（S001〜S003 と同じセッション） |
| S005 | 2026-10-23 | P2 | リモート編集でキャレットが飛ばないようにし、見出しを title 列へ写し、切断中の編集の再接続後の復元を E2E で確かめた | `feature/s005-caret-reconnect` | 完了 | [slides](S005-caret-reconnect/slides.html) | [解説書](S005-caret-reconnect/解説書.md) | [log](../../log/sessions/2026-10-22-fdaf1939-ea4d-47eb-856a-abcdf5ffa999.md)（S001〜S004 と同じセッション） |
| S006 | 2026-10-23 | P2 | Presence（参加者の一覧）と他の人のキャレット・選択範囲の表示 | `feature/s006-presence-cursors` | 完了 | [slides](S006-presence-cursors/slides.html) | [解説書](S006-presence-cursors/解説書.md) | [log](../../log/sessions/2026-10-22-fdaf1939-ea4d-47eb-856a-abcdf5ffa999.md)（S001〜S005 と同じセッション） |
| S007 | 2026-10-24 | P2 | S006 レビューの指摘を直す: 相手のキャレットが 1 文字遅れる不具合（文書を測る）、名前のバイト上限、選択範囲の帯のはみ出し | `feature/s007-review-fixes` | 完了 | [slides](S007-review-fixes/slides.html) | [解説書](S007-review-fixes/解説書.md) | [log](../../log/sessions/2026-10-24-c03403db-ff3c-4ac5-ac00-19e7f00f5334.md) |
| S008 | 2026-10-24 | P2 | ブロックの種類（箇条書き・ToDo・コード・引用・区切り線・トグル）と入れ子（indent）。P2 の作業の項目が全部済んだ | `feature/s008-block-types` | 完了 | [slides](S008-block-types/slides.html) | [解説書](S008-block-types/解説書.md) | [log](../../log/sessions/2026-10-24-c03403db-ff3c-4ac5-ac00-19e7f00f5334.md)（S007 と同じセッション） |
| S009 | 2026-10-25 | P3 | フォーミュラ言語（字句解析・構文解析・型検査・評価）と例題集。P3 の完了条件の半分 | `feature/s009-formula` | 完了 | [slides](S009-formula/slides.html) | [解説書](S009-formula/解説書.md) | [log](../../log/sessions/2026-10-24-c03403db-ff3c-4ac5-ac00-19e7f00f5334.md)（S007・S008 と同じセッション） |
