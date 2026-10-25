# Fakers Notion に要る機能

Notion を参考に、Fakers Notion に要る機能を洗い出した。Phase は [roadmap.md](roadmap.md) の区分。

- 確認日: 2026-10-22。Notion の機能は一般に知られている範囲で挙げた（出典: <https://www.notion.com/help>、確認日 2026-10-22）。細部の挙動は【未確認】。
- 優先度:
  - **Must**: 最初の公開に必須
  - **Should**: 公開後すぐに要る
  - **Could**: 余裕があれば

## 1. ページとブロック

| 機能 | 優先度 | Phase | Fakers Notion での方針 |
| --- | --- | --- | --- |
| ページの作成・一覧・開く | Must | P1（S002 で済） | `GET/POST /api/pages`、Lustre の一覧 |
| 段落・見出しブロックの編集 | Must | P1（S002 で済） | `Y.Array("blocks")` の `Y.Map{id,type,text:Y.Text}`。[architecture.md](architecture.md#4-ブロックモデルと-json-の契約) |
| Enter で新しいブロック、種別の切り替え（削除も） | Must | P1（S002 で済） | FFI の `insert_block_after` / `set_kind` |
| リスト・ToDo・コード・引用・区切り・トグル | Must | P2（S008 で済） | `type` の追加。`checked` と `indent` は `Y.Map` のキー。入れ子は `indent`（Tab / Shift+Tab）、トグルは自分より深い後続のブロックを畳む。番号付きリストは未対応 |
| キャレットを保つ編集（contenteditable） | Should | P2 | P1 は controlled input。リモート編集でキャレットが末尾に飛ぶ既知の制限 |
| ブロックの並べ替え（ドラッグ） | Should | P2 | `Y.Array` の move。yjs の move は実験的なので、delete + insert で代用【未確認】 |
| インライン書式（太字・リンク・コード） | Should | P2 | `Y.Text` の属性 |
| 画像・ファイル | Could | P6 | アップロードの置き場が要る |
| ページの階層（ネスト）とサイドバー | Must | P4 | `parent_id`。P1 は平らな一覧 |
| テンプレート | Could | — | 未定 |

## 2. 共同編集

| 機能 | 優先度 | Phase | 方針 |
| --- | --- | --- | --- |
| リアルタイム同期（複数タブ・複数人） | Must | P1（S002 で済。タブ間 約 5 ms） | Phoenix Channel のバイナリ、yjs / yrs の update v1 |
| 再起動しても残る | Must | P1（S002 で済） | `DocumentServer` の flush → SQLite |
| 切断中の編集の回復 | Must | P1（S002 で実装。E2E では未検証） | `sync` の state vector から差分を push |
| Presence（誰が開いているか）とカーソル | Should | P2 | `Phoenix.Presence` と yjs の awareness |
| 履歴（版の比較と復元） | Could | P6 | yrs の snapshot【未確認】 |
| コメント | Could | — | 未定 |

## 3. データベース

| 機能 | 優先度 | Phase | 方針 |
| --- | --- | --- | --- |
| テーブル・ボード・リストのビュー | Must | P3 | ビューはページの中のブロック。データは `Y.Map` の行 |
| プロパティ（テキスト・数値・選択・日付・チェック） | Must | P3 | 型は `fakers_shared` に置く |
| フィルタとソート | Must | P3 | クライアント側で評価。大きくなったら Rust |
| フォーミュラ | Must | P3 | **Rust の字句解析・構文解析・型検査・評価器**。両側（NIF と、P5 で WASM）で同じ実装。S009 で言語と例題集を済（[ADR-0007](adr/0007-formula-language.md)） |
| リレーションとロールアップ | Should | P3 | フォーミュラの後 |
| カレンダー・ギャラリーのビュー | Could | P3 | テーブルの後 |

## 4. ワークスペースと権限

| 機能 | 優先度 | Phase | 方針 |
| --- | --- | --- | --- |
| ユーザーと認証 | Must | P4 | `phx.gen.auth` か、外部 IdP。未定 |
| ワークスペース、共有、権限（閲覧・編集） | Must | P4 | Channel の join で検査 |
| 公開リンク | Could | P4 | 未定 |

## 5. 分散と運用

| 機能 | 優先度 | Phase | 方針 |
| --- | --- | --- | --- |
| 複数ノードで文書プロセスを分散 | Should | P5 | libcluster + Horde。状態は BEAM 側のバイナリ（[ADR-0003](adr/0003-crdt-yjs-yrs.md)） |
| 接続を切らずにコードを差し替える | Should | P5 | OTP リリースと relup。NIF は差し替えない設計 |
| Postgres | Should | P5 | 複数ノードで共有する DB。P1〜P4 は SQLite（[ADR-0005](adr/0005-persistence-sqlite.md)） |
| Rust コアの WASM 化 | Could | P5 | クライアントとサーバで同じ実装 |

## 6. 検索・入出力

| 機能 | 優先度 | Phase | 方針 |
| --- | --- | --- | --- |
| 全文検索 | Should | P6 | tantivy（Rust） |
| Markdown / HTML のエクスポート | Should | P6 | Rust |
| Markdown のインポート | Could | P6 | Rust |
| 公開 API | Could | — | Phoenix の JSON API を広げる |
