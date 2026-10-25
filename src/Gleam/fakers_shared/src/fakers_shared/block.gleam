//// ブロック。Rust の `blocks_json` と JS の FFI が出す `[{"id","type","text","checked","indent"}]` と同じ形。
//// Erlang 側では `{block, Id, Kind, Text, Checked, Indent}`。
//// `checked` は ToDo のチェック、`indent` は入れ子の深さ（トグルは自分より深い後続のブロックを畳む）。
//// データベース（`Database`）の `text` は表の題名。列と行は `fakers_shared/database` が別に読む。

import gleam/dynamic/decode
import gleam/json

pub type BlockKind {
  Paragraph
  Heading
  Bulleted
  Todo
  Code
  Quote
  Divider
  Toggle
  Database
}

pub type Block {
  Block(id: String, kind: BlockKind, text: String, checked: Bool, indent: Int)
}

/// 選べる種類の一覧（表示の順）。
pub const kinds = [
  Paragraph,
  Heading,
  Bulleted,
  Todo,
  Code,
  Quote,
  Divider,
  Toggle,
  Database,
]

pub fn kind_to_string(kind: BlockKind) -> String {
  case kind {
    Paragraph -> "paragraph"
    Heading -> "heading"
    Bulleted -> "bulleted"
    Todo -> "todo"
    Code -> "code"
    Quote -> "quote"
    Divider -> "divider"
    Toggle -> "toggle"
    Database -> "database"
  }
}

pub fn kind_from_string(s: String) -> Result(BlockKind, Nil) {
  case s {
    "paragraph" -> Ok(Paragraph)
    "heading" -> Ok(Heading)
    "bulleted" -> Ok(Bulleted)
    "todo" -> Ok(Todo)
    "code" -> Ok(Code)
    "quote" -> Ok(Quote)
    "divider" -> Ok(Divider)
    "toggle" -> Ok(Toggle)
    "database" -> Ok(Database)
    _ -> Error(Nil)
  }
}

pub fn kind_decoder() -> decode.Decoder(BlockKind) {
  use s <- decode.then(decode.string)
  case kind_from_string(s) {
    Ok(kind) -> decode.success(kind)
    Error(Nil) -> decode.failure(Paragraph, "BlockKind")
  }
}

pub fn block_decoder() -> decode.Decoder(Block) {
  use id <- decode.field("id", decode.string)
  use kind <- decode.field("type", kind_decoder())
  use text <- decode.field("text", decode.string)
  use checked <- decode.optional_field("checked", False, decode.bool)
  use indent <- decode.optional_field("indent", 0, decode.int)
  decode.success(Block(id:, kind:, text:, checked:, indent:))
}

pub fn blocks_decoder() -> decode.Decoder(List(Block)) {
  decode.list(block_decoder())
}

/// JSON の文字列からブロックの一覧へ。
pub fn decode_blocks(input: String) -> Result(List(Block), json.DecodeError) {
  json.parse(input, blocks_decoder())
}

pub fn block_to_json(block: Block) -> json.Json {
  json.object([
    #("id", json.string(block.id)),
    #("type", json.string(kind_to_string(block.kind))),
    #("text", json.string(block.text)),
    #("checked", json.bool(block.checked)),
    #("indent", json.int(block.indent)),
  ])
}

pub fn blocks_to_json(blocks: List(Block)) -> json.Json {
  json.array(blocks, block_to_json)
}
