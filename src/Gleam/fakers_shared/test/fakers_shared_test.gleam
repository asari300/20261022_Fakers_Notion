import fakers_shared/block.{Block, Heading, Paragraph, Todo}
import fakers_shared/page.{PageSummary}
import gleam/json
import gleam/list
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

/// Rust の blocks_json がそのまま出す形（new_page("T", "h1", "p1")）。
const rust_fixture =
  "[{\"checked\":false,\"id\":\"h1\",\"indent\":0,\"text\":\"T\",\"type\":\"heading\"},{\"checked\":false,\"id\":\"p1\",\"indent\":0,\"text\":\"\",\"type\":\"paragraph\"}]"

pub fn decode_rust_fixture_test() {
  block.decode_blocks(rust_fixture)
  |> should.equal(
    Ok([
      Block("h1", Heading, "T", False, 0),
      Block("p1", Paragraph, "", False, 0),
    ]),
  )
}

pub fn block_round_trip_test() {
  let blocks = [
    Block("a", Heading, "見出し", False, 0),
    Block("b", Todo, "😀 本文", True, 2),
  ]
  blocks
  |> block.blocks_to_json
  |> json.to_string
  |> block.decode_blocks
  |> should.equal(Ok(blocks))
}

pub fn unknown_kind_is_error_test() {
  block.decode_blocks("[{\"id\":\"x\",\"type\":\"table\",\"text\":\"\"}]")
  |> should.be_error
}

/// S007 までの文書には checked と indent のキーが無い。
pub fn old_block_without_attrs_test() {
  block.decode_blocks("[{\"id\":\"x\",\"type\":\"heading\",\"text\":\"T\"}]")
  |> should.equal(Ok([Block("x", Heading, "T", False, 0)]))
}

pub fn missing_field_is_error_test() {
  block.decode_blocks("[{\"id\":\"x\",\"type\":\"heading\"}]")
  |> should.be_error
}

pub fn kind_strings_test() {
  block.kind_to_string(Heading) |> should.equal("heading")
  block.kind_from_string("paragraph") |> should.equal(Ok(Paragraph))
  block.kind_from_string("nope") |> should.equal(Error(Nil))
  list.each(block.kinds, fn(k) {
    block.kind_from_string(block.kind_to_string(k)) |> should.equal(Ok(k))
  })
}

pub fn page_round_trip_test() {
  let p = PageSummary("0193", "My page")
  p
  |> page.page_to_json
  |> json.to_string
  |> page.decode_page
  |> should.equal(Ok(p))

  page.decode_pages(
    "[{\"id\":\"1\",\"title\":\"A\"},{\"id\":\"2\",\"title\":\"B\"}]",
  )
  |> should.equal(Ok([PageSummary("1", "A"), PageSummary("2", "B")]))
}
