//// 編集セッション（yjs の Y.Doc と Phoenix の Channel）への束縛。
//// 中身は session.ffi.mjs。バイト列は JS の中に閉じ込め、Gleam には JSON の文字列だけが来る。

/// JS 側のセッションオブジェクト。中身には触らない。
pub type Session

/// 接続して `doc:<id>` に参加する。`on_blocks` は sync の後と文書が変わるたびに
/// ブロック一覧の JSON を受け取り、`on_status` は
/// "connecting" | "joined" | "error: <理由>" | "closed" を受け取る。
/// `on_peers` は自分以外の参加者の JSON `[{"id","name","color"}]` を受け取る
/// （カーソルの描画は JS 側で行う）。
@external(javascript, "./session.ffi.mjs", "open")
pub fn open(
  doc_id: String,
  on_blocks: fn(String) -> Nil,
  on_status: fn(String) -> Nil,
  on_peers: fn(String) -> Nil,
) -> Session

/// ブロックの文字列を `new_text` にする（差分だけを Y.Text に反映する）。
@external(javascript, "./session.ffi.mjs", "set_text")
pub fn set_text(session: Session, block_id: String, new_text: String) -> Nil

/// `block_id` の直後に深さ `indent` の空のブロックを足し、新しい id を返す。
@external(javascript, "./session.ffi.mjs", "insert_block_after")
pub fn insert_block_after(
  session: Session,
  block_id: String,
  kind: String,
  indent: Int,
) -> String

/// ブロックの種類（`block.kind_to_string` の値）を変える。
@external(javascript, "./session.ffi.mjs", "set_kind")
pub fn set_kind(session: Session, block_id: String, kind: String) -> Nil

/// ToDo のチェックを付け外す。
@external(javascript, "./session.ffi.mjs", "set_checked")
pub fn set_checked(session: Session, block_id: String, checked: Bool) -> Nil

/// 入れ子の深さを変える。
@external(javascript, "./session.ffi.mjs", "set_indent")
pub fn set_indent(session: Session, block_id: String, indent: Int) -> Nil

/// ブロックを消す。最後の 1 つは消さない。
@external(javascript, "./session.ffi.mjs", "delete_block")
pub fn delete_block(session: Session, block_id: String) -> Nil

/// 退室して切断する。以後コールバックは呼ばれない。
@external(javascript, "./session.ffi.mjs", "close")
pub fn close(session: Session) -> Nil

/// 描画の後で `block-<id>` の入力欄にフォーカスする。
@external(javascript, "./session.ffi.mjs", "focus_block")
pub fn focus_block(block_id: String) -> Nil

/// 文字列の差分 #(開始位置, 削除する長さ, 挿入する文字列)。位置と長さは UTF-16 単位。
@external(javascript, "./session.ffi.mjs", "diff_text")
pub fn diff_text(old: String, new: String) -> #(Int, Int, String)
