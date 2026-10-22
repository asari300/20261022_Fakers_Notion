# セッションの索引

各セッションのスライドと解説書。書き方は `.claude/skills/session-docs/SKILL.md`、雛形は [_template/](_template/)。

| S | 日付 | Phase | 題名 | ブランチ | 状態 | スライド | 解説書 | セッション記録 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| S001 | 2026-10-22 | P0 | 運用基盤と計画: CLAUDE.md、スキル、セッション記録のフック、正典の文書と ADR、P1 の計画 | `feature/s001-ops-and-plan` | 完了 | [slides](S001-ops-and-plan/slides.html) | [解説書](S001-ops-and-plan/解説書.md) | [log](../../log/sessions/2026-10-22-fdaf1939-ea4d-47eb-856a-abcdf5ffa999.md) |
| S002 | 2026-10-22 | P1 | 骨組みと最初の縦スライス: Rust workspace（fakers_core / fakers_nif）、Gleam（fakers_shared / fakers_web）、Phoenix（fakers）、ページの作成・編集・リアルタイム同期（タブ間 約 5 ms）・SQLite への永続化、2 タブの E2E。相互運用ゲート（yrs ⇄ yjs）が通り ADR-0003・0004 を Accepted に | `feature/s002-vertical-slice` | 完了 | [slides](S002-vertical-slice/slides.html) | [解説書](S002-vertical-slice/解説書.md) | [log](../../log/sessions/2026-10-22-fdaf1939-ea4d-47eb-856a-abcdf5ffa999.md)（S001 と同じセッション） |
| S003 | 2026-10-22 | P1 | ライセンスを MIT OR Apache-2.0 に決め、GitHub Actions の CI を足した（ADR-0006） | `feature/s003-ci-license` | 完了 | [slides](S003-ci-license/slides.html) | [解説書](S003-ci-license/解説書.md) | [log](../../log/sessions/2026-10-22-fdaf1939-ea4d-47eb-856a-abcdf5ffa999.md)（S001・S002 と同じセッション） |
| S004 | 2026-10-23 | 運用 | worktree の実体を USB に移し、SD と速度を比べた（冷間ビルド 52 分 → 24 分） | `feature/s004-usb-bench` | 完了 | — | [作業記録](../../log/work/2026-10-23-s004-usb-worktrees.md) | [log](../../log/sessions/2026-10-22-fdaf1939-ea4d-47eb-856a-abcdf5ffa999.md)（S001〜S003 と同じセッション） |
| S005 | 2026-10-23 | P2 | リモート編集でキャレットが飛ばないようにし、見出しを title 列へ写し、切断中の編集の再接続後の復元を E2E で確かめた | `feature/s005-caret-reconnect` | 完了 | [slides](S005-caret-reconnect/slides.html) | [解説書](S005-caret-reconnect/解説書.md) | [log](../../log/sessions/2026-10-22-fdaf1939-ea4d-47eb-856a-abcdf5ffa999.md)（S001〜S004 と同じセッション） |
