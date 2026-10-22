# ADR-0002 言語の役割分担

- 状態: **Accepted**（2026-10-22、S001）。

## 背景

- ユーザーの方針（2026-10-22）: 「メインは Rust, Gleam, Elixir で作成する。コアは Rust、分散処理やホットスワップの仕組みを活かすなら Elixir や Gleam」。
- 3 言語を同じ層で混ぜると、同じ概念が 3 回定義される（三言語税）。境界を先に決める。
- Gleam は Erlang と JavaScript の両方にコンパイルできる。これが Elixir に無い固有の価値で、型をクライアントとサーバで共有できる。
- Gleam の OTP 対応（gleam_otp 1.x、actor と static_supervisor）は Elixir より薄い（[research/stack.md](../research/stack.md)）。

## 決定

| 言語 | 受け持つもの | 受け持たないもの |
| --- | --- | --- |
| **Rust** | コア: ブロック文書モデル、CRDT（yrs）、将来のフォーミュラ言語・全文検索・エクスポート。Elixir からは Rustler の NIF（dirty scheduler）で呼ぶ。**純関数**として呼び、状態は呼び出し側が持つ | プロセス、配信、I/O |
| **Elixir / Phoenix** | リアルタイムと分散: Channel、文書ごとの GenServer と監視ツリー、PubSub、Presence、Ecto、認証、ジョブ、クラスタ（libcluster / Horde）、OTP リリースとホットスワップ | CRDT の計算、ブロックの解釈 |
| **Gleam** | 両ターゲットで共有する型（ブロック、ページ、操作）と、Lustre の SPA | プロセス・監視・分散（Elixir に寄せる）。Gleam と Elixir を同じ層で混ぜない |
| **Python** | ツール用途（文書の検査など） | 製品のロジック |

- 境界をまたぐ契約は 2 つだけ: **JSON の形**（`[{"id","type","text"}]`、Rust と JS が同じものを出し、Gleam のデコーダが読む）と **yjs の update v1 のバイト列**（クライアントとサーバの間、サーバと Rust の間）。
- 選択肢と理由:
  - Rust を WASM にしてクライアントでも使う案は P5 に回す（二重ビルドと非同期初期化の費用。[ADR-0003](0003-crdt-yjs-yrs.md)）。
  - UI を TypeScript / React にする案は、Gleam の型共有の価値を失うので採らない（ユーザーの選択: Gleam / Lustre）。
  - Gleam でサーバの一部（Wisp / Mist）を書く案は、Phoenix の Channel・Presence・PubSub の成熟度に劣るので採らない。

## 結果

- ディレクトリは `src/Rust`（workspace）、`src/Elixir/fakers`、`src/Gleam/fakers_shared`、`src/Gleam/fakers_web`、`src/Python/mod/fakers_notion`（[architecture.md](../architecture.md#21-ディレクトリ)）。
- ホットスワップしたい状態は BEAM 側に置く。これは Rust が純関数であることの帰結（[ADR-0003](0003-crdt-yjs-yrs.md)）。
