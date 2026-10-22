# ADR（設計判断の記録）

| 番号 | 題名 | 状態 |
| --- | --- | --- |
| [0001](0001-toolchain.md) | ツールチェーン（uv・cargo / rustup・mise の分担） | Accepted |
| [0002](0002-language-roles.md) | 言語の役割分担（Rust コア、Elixir リアルタイムと分散、Gleam 共有する型と UI、Python ツール） | Accepted |
| [0003](0003-crdt-yjs-yrs.md) | CRDT はクライアント yjs・サーバ yrs。文書の状態は BEAM 側のバイナリで持ち、NIF は純関数にする | Accepted |
| [0004](0004-gleam-integration.md) | Gleam は mix.exs のカスタムコンパイラで組み込み、UI は Lustre + esbuild（mix_gleam と lustre_dev_tools を使わない） | Accepted |
| [0005](0005-persistence-sqlite.md) | 永続化は SQLite（ecto_sqlite3）から始める | Accepted |
| [0006](0006-license-and-ci.md) | ライセンスは MIT OR Apache-2.0、CI は毎回全部を検査する | Accepted |

書式: `NNNN-<題名>.md`。章は「状態 / 背景 / 決定 / 結果」の4つ。決定を覆すときは古い ADR を消さず、状態を Superseded にして新しい番号で書く。Proposed の ADR は、実装で確かめたセッションで Accepted にする。
