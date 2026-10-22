# S004 worktree を USB へ移す・速度計測

- `/mnt/sdc1` は無く、同じドライブが `/mnt/usb_sd64c`（ext4, 58G）。`/mnt/usb_sd64c/Fakers_Notion` を作って所有者を変更。
- 実体は USB、`.git-worktree/<topic>` から symlink（Colorful_DL4mine と同じ方式）。
- 旧 s002/s003 はマージ済みなので削除（`git worktree move` はデバイス越え不可）。

## 計測（冷間、同一コミット b5aa348、RPi 500）

| | SD (mmcblk0) | USB (sdc1) |
|---|---|---|
| dd 書き込み 512MB | 3.0 MB/s | 52.9 MB/s |
| dd 読み込み | 57.1 MB/s | 90.8 MB/s |
| mise run setup | 474s | 259s |
| test:rust | 1595s | 608s |
| test:shared | 302s | 8s |
| test:web | 9s | 1s |
| test:elixir | 635s | 586s |
| 合計 | 52m26s | 24m23s |

- CPU 時間（user）はほぼ同じ（131s と 133s）なので差は I/O 待ち。
- 注意: USB を先に走らせたので hex/mise の共有キャッシュは SD 側に有利。SD の書き込みは計測時に特に遅かった（同時間帯の SD 負荷に左右される）。1 回ずつの値。
