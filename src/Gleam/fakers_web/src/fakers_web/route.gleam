//// ハッシュによる画面遷移。`#/` = ページ一覧、`#/p/<id>` = ページ。

import gleam/string

pub type Route {
  PageList
  PageView(id: String)
}

/// ハッシュ文字列（"#/p/abc" など）を画面に変換する。分からないものは一覧。
pub fn parse(hash: String) -> Route {
  let path = case hash {
    "#" <> rest -> rest
    _ -> hash
  }
  case path {
    "/p/" <> id ->
      case string.is_empty(id) {
        True -> PageList
        False -> PageView(id)
      }
    _ -> PageList
  }
}

pub fn to_hash(route: Route) -> String {
  case route {
    PageList -> "#/"
    PageView(id) -> "#/p/" <> id
  }
}

@external(javascript, "./route.ffi.mjs", "get_hash")
pub fn get_hash() -> String

@external(javascript, "./route.ffi.mjs", "set_hash")
pub fn set_hash(hash: String) -> Nil

@external(javascript, "./route.ffi.mjs", "on_hash_change")
pub fn on_hash_change(callback: fn(String) -> Nil) -> Nil
