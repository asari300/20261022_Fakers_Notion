//// データベース（`type: "database"` のブロック）の列と行。
//// JS の FFI はブロックの JSON に `"table": {"columns": [...], "rows": [...]}` を足す:
////   columns: `[{"id", "name", "type": "text" | "number" | "checkbox"}]`
////   rows:    `[{"id", "cells": {<列の id>: 文字列 | 数値 | 真偽値}}]`
//// セルの値は列の型と合うときだけ読む（列の型を変えた後の古い値や、壊れた値は空として扱う）。

import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result

pub type PropType {
  TextProp
  NumberProp
  CheckboxProp
}

/// 選べる列の型（表示の順）。
pub const prop_types = [TextProp, NumberProp, CheckboxProp]

pub type Column {
  Column(id: String, name: String, prop: PropType)
}

pub type Cell {
  TextCell(String)
  NumberCell(Float)
  CheckboxCell(Bool)
  EmptyCell
}

pub type Row {
  Row(id: String, cells: Dict(String, Cell))
}

pub type Table {
  Table(columns: List(Column), rows: List(Row))
}

pub fn prop_to_string(prop: PropType) -> String {
  case prop {
    TextProp -> "text"
    NumberProp -> "number"
    CheckboxProp -> "checkbox"
  }
}

pub fn prop_from_string(s: String) -> Result(PropType, Nil) {
  case s {
    "text" -> Ok(TextProp)
    "number" -> Ok(NumberProp)
    "checkbox" -> Ok(CheckboxProp)
    _ -> Error(Nil)
  }
}

/// 行のセルのうち、列の型と合う値。無いか型が違えば `EmptyCell`。
pub fn cell(row: Row, column: Column) -> Cell {
  case column.prop, dict.get(row.cells, column.id) {
    TextProp, Ok(TextCell(_) as c)
    | NumberProp, Ok(NumberCell(_) as c)
    | CheckboxProp, Ok(CheckboxCell(_) as c)
    -> c
    _, _ -> EmptyCell
  }
}

/// FFI の `set_cell` に渡す値。`EmptyCell` は null（セルを消す）。
pub fn cell_to_json(c: Cell) -> json.Json {
  case c {
    TextCell(s) -> json.string(s)
    NumberCell(x) -> json.float(x)
    CheckboxCell(b) -> json.bool(b)
    EmptyCell -> json.null()
  }
}

fn cell_decoder() -> decode.Decoder(Cell) {
  decode.one_of(decode.map(decode.string, TextCell), [
    decode.map(decode.bool, CheckboxCell),
    decode.map(decode.float, NumberCell),
    decode.map(decode.int, fn(n) { NumberCell(int.to_float(n)) }),
    // 知らない形の値で表ごと読めなくならないように
    decode.map(decode.dynamic, fn(_) { EmptyCell }),
  ])
}

fn column_decoder() -> decode.Decoder(Column) {
  use id <- decode.field("id", decode.string)
  use name <- decode.field("name", decode.string)
  use prop <- decode.optional_field("type", "text", decode.string)
  decode.success(
    Column(id:, name:, prop: case prop_from_string(prop) {
      Ok(p) -> p
      Error(Nil) -> TextProp
    }),
  )
}

fn row_decoder() -> decode.Decoder(Row) {
  use id <- decode.field("id", decode.string)
  use cells <- decode.optional_field(
    "cells",
    dict.new(),
    decode.dict(decode.string, cell_decoder()),
  )
  decode.success(Row(id:, cells:))
}

pub fn table_decoder() -> decode.Decoder(Table) {
  use columns <- decode.optional_field(
    "columns",
    [],
    decode.list(column_decoder()),
  )
  use rows <- decode.optional_field("rows", [], decode.list(row_decoder()))
  decode.success(Table(columns:, rows:))
}

/// ブロック一覧の JSON から、`table` を持つブロックの id → 表。
pub fn decode_tables(
  input: String,
) -> Result(Dict(String, Table), json.DecodeError) {
  let entry = {
    use id <- decode.field("id", decode.string)
    use table <- decode.optional_field(
      "table",
      None,
      decode.optional(table_decoder()),
    )
    decode.success(#(id, table))
  }
  use entries <- result.map(json.parse(input, decode.list(entry)))
  list.fold(entries, dict.new(), fn(acc, e) {
    case e {
      #(id, Some(t)) -> dict.insert(acc, id, t)
      #(_, None) -> acc
    }
  })
}
