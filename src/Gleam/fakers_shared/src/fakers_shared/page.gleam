//// ページの要約。`GET /api/pages` と `POST /api/pages` が返す `{"id","title"}`。

import gleam/dynamic/decode
import gleam/json

pub type PageSummary {
  PageSummary(id: String, title: String)
}

pub fn page_decoder() -> decode.Decoder(PageSummary) {
  use id <- decode.field("id", decode.string)
  use title <- decode.field("title", decode.string)
  decode.success(PageSummary(id:, title:))
}

pub fn pages_decoder() -> decode.Decoder(List(PageSummary)) {
  decode.list(page_decoder())
}

pub fn decode_page(input: String) -> Result(PageSummary, json.DecodeError) {
  json.parse(input, page_decoder())
}

pub fn decode_pages(
  input: String,
) -> Result(List(PageSummary), json.DecodeError) {
  json.parse(input, pages_decoder())
}

pub fn page_to_json(page: PageSummary) -> json.Json {
  json.object([
    #("id", json.string(page.id)),
    #("title", json.string(page.title)),
  ])
}
