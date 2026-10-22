import fakers_shared/block.{Block, Heading, Paragraph}
import fakers_shared/page.{PageSummary}
import gleam/json
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

/// Rust の blocks_json がそのまま出す形（new_page("T", "h1", "p1")）。
const rust_fixture = "[{\"id\":\"h1\",\"type\":\"heading\",\"text\":\"T\"},{\"id\":\"p1\",\"type\":\"paragraph\",\"text\":\"\"}]"

pub fn decode_rust_fixture_test() {
  block.decode_blocks(rust_fixture)
  |> should.equal(
    Ok([Block("h1", Heading, "T"), Block("p1", Paragraph, "")]),
  )
}

pub fn block_round_trip_test() {
  let blocks = [Block("a", Heading, "見出し"), Block("b", Paragraph, "😀 本文")]
  blocks
  |> block.blocks_to_json
  |> json.to_string
  |> block.decode_blocks
  |> should.equal(Ok(blocks))
}

pub fn unknown_kind_is_error_test() {
  block.decode_blocks("[{\"id\":\"x\",\"type\":\"toggle\",\"text\":\"\"}]")
  |> should.be_error
}

pub fn missing_field_is_error_test() {
  block.decode_blocks("[{\"id\":\"x\",\"type\":\"heading\"}]")
  |> should.be_error
}

pub fn kind_strings_test() {
  block.kind_to_string(Heading) |> should.equal("heading")
  block.kind_from_string("paragraph") |> should.equal(Ok(Paragraph))
  block.kind_from_string("nope") |> should.equal(Error(Nil))
}

pub fn page_round_trip_test() {
  let p = PageSummary("0193", "My page")
  p
  |> page.page_to_json
  |> json.to_string
  |> page.decode_page
  |> should.equal(Ok(p))

  page.decode_pages("[{\"id\":\"1\",\"title\":\"A\"},{\"id\":\"2\",\"title\":\"B\"}]")
  |> should.equal(Ok([PageSummary("1", "A"), PageSummary("2", "B")]))
}
