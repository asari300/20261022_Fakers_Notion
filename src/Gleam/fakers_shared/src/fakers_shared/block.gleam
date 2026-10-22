//// ブロック。Rust の `blocks_json` と JS の FFI が出す `[{"id","type","text"}]` と同じ形。
//// Erlang 側では `{block, Id, heading | paragraph, Text}`。

import gleam/dynamic/decode
import gleam/json

pub type BlockKind {
  Paragraph
  Heading
}

pub type Block {
  Block(id: String, kind: BlockKind, text: String)
}

pub fn kind_to_string(kind: BlockKind) -> String {
  case kind {
    Paragraph -> "paragraph"
    Heading -> "heading"
  }
}

pub fn kind_from_string(s: String) -> Result(BlockKind, Nil) {
  case s {
    "paragraph" -> Ok(Paragraph)
    "heading" -> Ok(Heading)
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
  decode.success(Block(id:, kind:, text:))
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
  ])
}

pub fn blocks_to_json(blocks: List(Block)) -> json.Json {
  json.array(blocks, block_to_json)
}
