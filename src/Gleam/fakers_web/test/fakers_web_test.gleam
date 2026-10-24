import fakers_shared/block.{Block, Heading, Paragraph, Toggle}
import fakers_web
import fakers_web/route
import fakers_web/session
import gleam/list
import gleam/set
import gleeunit

pub fn main() -> Nil {
  gleeunit.main()
}

// diff_text: 位置と長さは UTF-16 単位

pub fn diff_identical_test() {
  assert session.diff_text("hello", "hello") == #(5, 0, "")
}

pub fn diff_empty_test() {
  assert session.diff_text("", "") == #(0, 0, "")
  assert session.diff_text("", "abc") == #(0, 0, "abc")
}

pub fn diff_append_test() {
  assert session.diff_text("abc", "abcdef") == #(3, 0, "def")
}

pub fn diff_prepend_test() {
  assert session.diff_text("abc", "xyabc") == #(0, 0, "xy")
}

pub fn diff_middle_replace_test() {
  assert session.diff_text("hello world", "hello there world")
    == #(6, 0, "there ")
  assert session.diff_text("abcdef", "abXYef") == #(2, 2, "XY")
}

pub fn diff_delete_test() {
  assert session.diff_text("abcdef", "abef") == #(2, 2, "")
  assert session.diff_text("abc", "") == #(0, 3, "")
}

pub fn diff_repeated_chars_test() {
  // 同じ文字が続くときも長さの辻褄が合う
  assert session.diff_text("aaa", "aaaa") == #(3, 0, "a")
}

pub fn diff_emoji_test() {
  // 😀 は UTF-16 で 2 単位
  assert session.diff_text("a", "a😀") == #(1, 0, "😀")
  assert session.diff_text("😀b", "😀c") == #(2, 1, "c")
  assert session.diff_text("x😀y", "xy") == #(1, 2, "")
  // サロゲートペアの途中では切らない（😀 と 😃 は上位サロゲートが同じ）
  assert session.diff_text("😀", "😃") == #(0, 2, "😃")
}

pub fn decode_blocks_test() {
  let json =
    "[{\"id\":\"h1\",\"type\":\"heading\",\"text\":\"Title\"},"
    <> "{\"text\":\"hello 😀\",\"type\":\"paragraph\",\"id\":\"p1\"}]"
  assert block.decode_blocks(json)
    == Ok([
      Block("h1", Heading, "Title", False, 0),
      Block("p1", Paragraph, "hello 😀", False, 0),
    ])
}

pub fn collapsed_toggle_hides_deeper_blocks_test() {
  let b = fn(id, kind, indent) { Block(id, kind, "", False, indent) }
  let blocks = [
    b("t", Toggle, 0),
    b("c1", Paragraph, 1),
    b("t2", Toggle, 1),
    b("c2", Paragraph, 2),
    b("after", Paragraph, 0),
  ]
  let ids = fn(collapsed) {
    fakers_web.visible_blocks(blocks, set.from_list(collapsed))
    |> list.map(fn(b) { b.id })
  }
  assert ids([]) == ["t", "c1", "t2", "c2", "after"]
  assert ids(["t"]) == ["t", "after"]
  assert ids(["t2"]) == ["t", "c1", "t2", "after"]
}

pub fn route_parse_test() {
  assert route.parse("") == route.PageList
  assert route.parse("#/") == route.PageList
  assert route.parse("#/p/abc-123") == route.PageView("abc-123")
  assert route.parse("#/p/") == route.PageList
  assert route.to_hash(route.PageView("x")) == "#/p/x"
}
