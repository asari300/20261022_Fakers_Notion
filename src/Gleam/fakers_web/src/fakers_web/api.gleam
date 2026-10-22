//// REST API（/api/pages）への要求。

import fakers_shared/page.{type PageSummary}
import gleam/json
import lustre/effect.{type Effect}
import rsvp

/// ページ一覧を取る。
pub fn list_pages(
  handler: fn(Result(List(PageSummary), rsvp.Error(String))) -> msg,
) -> Effect(msg) {
  rsvp.get("/api/pages", rsvp.expect_json(page.pages_decoder(), handler))
}

/// ページを作る。
pub fn create_page(
  title: String,
  handler: fn(Result(PageSummary, rsvp.Error(String))) -> msg,
) -> Effect(msg) {
  rsvp.post(
    "/api/pages",
    json.object([#("title", json.string(title))]),
    rsvp.expect_json(page.page_decoder(), handler),
  )
}
