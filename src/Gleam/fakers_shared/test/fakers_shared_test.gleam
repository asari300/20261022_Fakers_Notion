import fakers_shared/block.{Block, Database, Heading, Paragraph, Todo}
import fakers_shared/database.{
  CheckboxCell, CheckboxProp, Column, EmptyCell, NumberCell, NumberProp, Table,
  TextCell, TextProp,
}
import fakers_shared/page.{PageSummary}
import gleam/dict
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

/// FFI の snapshot がデータベースのブロックに足す `table`。
const table_fixture =
  "[{\"id\":\"p\",\"type\":\"paragraph\",\"text\":\"\"},{\"id\":\"d\",\"type\":\"database\",\"text\":\"本\",\"table\":{\"columns\":[{\"id\":\"c1\",\"name\":\"名前\",\"type\":\"text\"},{\"id\":\"c2\",\"name\":\"価格\",\"type\":\"number\"},{\"id\":\"c3\",\"name\":\"済み\",\"type\":\"checkbox\"},{\"id\":\"c4\",\"name\":\"謎\",\"type\":\"formula?\"}],\"rows\":[{\"id\":\"r1\",\"cells\":{\"c1\":\"りんご\",\"c2\":120,\"c3\":true,\"c4\":[1]}},{\"id\":\"r2\",\"cells\":{\"c1\":3.5,\"c2\":0.5}},{\"id\":\"r3\"}]}}]"

pub fn decode_tables_test() {
  let assert Ok(tables) = database.decode_tables(table_fixture)
  dict.keys(tables) |> should.equal(["d"])
  let assert Ok(Table(columns: [name, price, done, odd], rows: [r1, r2, r3])) =
    dict.get(tables, "d")
  name |> should.equal(Column("c1", "名前", TextProp))
  price.prop |> should.equal(NumberProp)
  done.prop |> should.equal(CheckboxProp)
  // 知らない列の型はテキストとして読む
  odd.prop |> should.equal(TextProp)
  database.cell(r1, name) |> should.equal(TextCell("りんご"))
  database.cell(r1, price) |> should.equal(NumberCell(120.0))
  database.cell(r1, done) |> should.equal(CheckboxCell(True))
  // 配列のような知らない値と、列の型と合わない値は空
  database.cell(r1, odd) |> should.equal(EmptyCell)
  database.cell(r2, name) |> should.equal(EmptyCell)
  database.cell(r2, price) |> should.equal(NumberCell(0.5))
  database.cell(r3, done) |> should.equal(EmptyCell)
  // ブロックの一覧としても読める
  let assert Ok([_, b]) = block.decode_blocks(table_fixture)
  b.kind |> should.equal(Database)
}

pub fn prop_strings_test() {
  list.each(database.prop_types, fn(p) {
    database.prop_from_string(database.prop_to_string(p)) |> should.equal(Ok(p))
  })
}
