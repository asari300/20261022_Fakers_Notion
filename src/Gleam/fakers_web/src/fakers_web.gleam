//// Fakers Notion の SPA。ページ一覧とページ（ブロックの編集）の 2 画面。
//// update は純粋に保ち、セッションの操作はすべて effect.from の中で行う。

import fakers_shared/block.{
  type Block, type BlockKind, Block, Bulleted, Code, Divider, Heading, Paragraph,
  Quote, Todo, Toggle,
}
import fakers_shared/page.{type PageSummary}
import fakers_web/api
import fakers_web/route.{type Route, PageList, PageView}
import fakers_web/session.{type Session}
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/set.{type Set}
import gleam/string
import lustre
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import rsvp

pub fn main() {
  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}

// MODEL -----------------------------------------------------------------------

pub type Model {
  Model(
    route: Route,
    pages: List(PageSummary),
    blocks: List(Block),
    status: String,
    peers: List(Peer),
    // 畳んだトグルの id。Notion と同じく開閉は自分の画面だけで、文書には書かない
    collapsed: Set(String),
    draft_title: String,
    session: Option(Session),
    error: Option(String),
  )
}

/// 同じページを開いている他の人。
pub type Peer {
  Peer(name: String, color: String)
}

pub type Msg {
  HashChanged(String)
  PagesLoaded(Result(List(PageSummary), rsvp.Error(String)))
  DraftChanged(String)
  CreatePage
  PageCreated(Result(PageSummary, rsvp.Error(String)))
  SessionOpened(doc_id: String, session: Session)
  BlocksChanged(String)
  StatusChanged(String)
  PeersChanged(String)
  TextEdited(block_id: String, text: String)
  EnterPressed(block_id: String)
  IndentPressed(block_id: String, delta: Int)
  KindChanged(block_id: String, kind: String)
  CheckToggled(block_id: String, checked: Bool)
  CollapseToggled(block_id: String)
  BlockDeleted(block_id: String)
}

fn init(_flags: Nil) -> #(Model, Effect(Msg)) {
  let current = route.parse(route.get_hash())
  let model =
    Model(
      route: current,
      pages: [],
      blocks: [],
      status: "",
      peers: [],
      collapsed: set.new(),
      draft_title: "",
      session: None,
      error: None,
    )
  #(
    model,
    effect.batch([
      subscribe_hash(),
      api.list_pages(PagesLoaded),
      enter_route(current),
    ]),
  )
}

// UPDATE ----------------------------------------------------------------------

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    HashChanged(hash) -> {
      let next = route.parse(hash)
      case next == model.route {
        True -> #(model, effect.none())
        False -> #(
          Model(
            ..model,
            route: next,
            blocks: [],
            status: "",
            peers: [],
            session: None,
            error: None,
          ),
          effect.batch([
            close_session(model.session),
            enter_route(next),
            case next {
              PageList -> api.list_pages(PagesLoaded)
              PageView(_) -> effect.none()
            },
          ]),
        )
      }
    }

    PagesLoaded(Ok(pages)) -> #(Model(..model, pages:), effect.none())
    PagesLoaded(Error(err)) -> #(
      Model(..model, error: Some("ページ一覧を読めませんでした: " <> describe(err))),
      effect.none(),
    )

    DraftChanged(text) -> #(Model(..model, draft_title: text), effect.none())

    CreatePage -> {
      let title = string.trim(model.draft_title)
      case title {
        "" -> #(model, effect.none())
        _ -> #(model, api.create_page(title, PageCreated))
      }
    }
    PageCreated(Ok(created)) -> #(
      Model(
        ..model,
        draft_title: "",
        pages: list.append(model.pages, [created]),
      ),
      // 遷移は hashchange 経由で HashChanged に任せる
      navigate(PageView(created.id)),
    )
    PageCreated(Error(err)) -> #(
      Model(..model, error: Some("ページを作れませんでした: " <> describe(err))),
      effect.none(),
    )

    SessionOpened(doc_id, s) ->
      case model.route {
        PageView(id) if id == doc_id -> #(
          Model(..model, session: Some(s)),
          effect.none(),
        )
        // 開いている間に別の画面へ移っていたら閉じる
        _ -> #(model, close_session(Some(s)))
      }

    BlocksChanged(json) ->
      case block.decode_blocks(json) {
        Ok(blocks) -> #(Model(..model, blocks:), effect.none())
        Error(_) -> #(
          Model(..model, error: Some("ブロックを読めませんでした")),
          effect.none(),
        )
      }

    StatusChanged(status) -> #(Model(..model, status:), effect.none())

    PeersChanged(raw) -> {
      let peer = {
        use name <- decode.field("name", decode.string)
        use color <- decode.field("color", decode.string)
        decode.success(Peer(name:, color:))
      }
      case json.parse(raw, decode.list(peer)) {
        Ok(peers) -> #(Model(..model, peers:), effect.none())
        Error(_) -> #(model, effect.none())
      }
    }

    TextEdited(id, text) -> {
      // 入力欄の値と食い違わないよう、手元のブロックも先に書き換える
      let blocks =
        list.map(model.blocks, fn(b) {
          case b.id == id {
            True -> Block(..b, text:)
            False -> b
          }
        })
      #(
        Model(..model, blocks:),
        with_session(model, fn(s) { session.set_text(s, id, text) }),
      )
    }

    EnterPressed(id) ->
      case list.find(model.blocks, fn(b) { b.id == id }) {
        Error(Nil) -> #(model, effect.none())
        // 空のリスト・ToDo・トグルで Enter を押したら、段落に戻して抜ける
        Ok(Block(kind: Bulleted, text: "", ..))
        | Ok(Block(kind: Todo, text: "", ..))
        | Ok(Block(kind: Toggle, text: "", ..)) -> #(
          model,
          with_session(model, fn(s) { session.set_kind(s, id, "paragraph") }),
        )
        Ok(b) -> {
          // リストと ToDo は同じ種類を続け、トグルは中身（1 段深い段落）を足して開く
          let #(kind, indent) = case b.kind {
            Bulleted | Todo -> #(b.kind, b.indent)
            Toggle -> #(Paragraph, b.indent + 1)
            _ -> #(Paragraph, b.indent)
          }
          #(
            Model(..model, collapsed: set.delete(model.collapsed, id)),
            with_session(model, fn(s) {
              let new_id =
                session.insert_block_after(
                  s,
                  id,
                  block.kind_to_string(kind),
                  indent,
                )
              session.focus_block(new_id)
            }),
          )
        }
      }

    IndentPressed(id, delta) -> {
      // 深さは 0 から「1 つ前のブロックより 1 段深い」まで
      let #(prev, found) =
        list.fold_until(model.blocks, #(-1, None), fn(acc, b) {
          case b.id == id {
            True -> list.Stop(#(acc.0, Some(b)))
            False -> list.Continue(#(b.indent, None))
          }
        })
      case found {
        None -> #(model, effect.none())
        Some(b) -> {
          let indent = int.clamp(b.indent + delta, 0, prev + 1)
          case indent == b.indent {
            True -> #(model, effect.none())
            False -> #(
              model,
              with_session(model, fn(s) { session.set_indent(s, id, indent) }),
            )
          }
        }
      }
    }

    KindChanged(id, kind) -> #(
      model,
      with_session(model, fn(s) { session.set_kind(s, id, kind) }),
    )

    CheckToggled(id, checked) -> #(
      model,
      with_session(model, fn(s) { session.set_checked(s, id, checked) }),
    )

    CollapseToggled(id) -> {
      let collapsed = case set.contains(model.collapsed, id) {
        True -> set.delete(model.collapsed, id)
        False -> set.insert(model.collapsed, id)
      }
      #(Model(..model, collapsed:), effect.none())
    }

    BlockDeleted(id) -> #(
      model,
      with_session(model, fn(s) { session.delete_block(s, id) }),
    )
  }
}

fn describe(err: rsvp.Error(String)) -> String {
  case err {
    rsvp.BadBody -> "応答の本文が不正です"
    rsvp.BadUrl(url) -> "URL が不正です: " <> url
    rsvp.HttpError(resp) -> "HTTP " <> string.inspect(resp.status)
    rsvp.JsonError(_) -> "JSON を解釈できません"
    rsvp.NetworkError -> "ネットワークエラー"
    rsvp.UnhandledResponse(resp) -> "想定外の応答 " <> string.inspect(resp.status)
  }
}

// EFFECTS ---------------------------------------------------------------------

/// hashchange を一度だけ購読する。
fn subscribe_hash() -> Effect(Msg) {
  use dispatch <- effect.from
  route.on_hash_change(fn(hash) { dispatch(HashChanged(hash)) })
}

/// 画面に入ったときの副作用。ページならセッションを開く。
fn enter_route(r: Route) -> Effect(Msg) {
  case r {
    PageList -> effect.none()
    PageView(id) -> {
      use dispatch <- effect.from
      let s =
        session.open(
          id,
          fn(json) { dispatch(BlocksChanged(json)) },
          fn(status) { dispatch(StatusChanged(status)) },
          fn(peers) { dispatch(PeersChanged(peers)) },
        )
      dispatch(SessionOpened(id, s))
    }
  }
}

fn close_session(s: Option(Session)) -> Effect(Msg) {
  case s {
    None -> effect.none()
    Some(s) -> effect.from(fn(_) { session.close(s) })
  }
}

fn navigate(r: Route) -> Effect(Msg) {
  effect.from(fn(_) { route.set_hash(route.to_hash(r)) })
}

fn with_session(model: Model, f: fn(Session) -> Nil) -> Effect(Msg) {
  case model.session {
    None -> effect.none()
    Some(s) -> effect.from(fn(_) { f(s) })
  }
}

// VIEW ------------------------------------------------------------------------

fn view(model: Model) -> Element(Msg) {
  html.main([attribute.class("app")], [
    case model.error {
      Some(message) -> html.p([attribute.class("error")], [html.text(message)])
      None -> element.none()
    },
    case model.route {
      PageList -> view_page_list(model)
      PageView(_) -> view_page(model)
    },
  ])
}

fn view_page_list(model: Model) -> Element(Msg) {
  html.section([attribute.class("page-list")], [
    html.h1([attribute.class("app-title")], [html.text("Fakers Notion")]),
    html.form(
      [attribute.class("new-page"), event.on_submit(fn(_) { CreatePage })],
      [
        html.input([
          attribute.type_("text"),
          attribute.class("new-page-input"),
          attribute.placeholder("新しいページのタイトル"),
          attribute.value(model.draft_title),
          event.on_input(DraftChanged),
        ]),
        html.button([attribute.type_("submit"), attribute.class("button")], [
          html.text("作成"),
        ]),
      ],
    ),
    html.ul(
      [attribute.class("pages")],
      list.map(model.pages, fn(p) {
        html.li([attribute.class("page-item")], [
          html.a([attribute.href(route.to_hash(PageView(p.id)))], [
            html.text(case p.title {
              "" -> "（無題）"
              t -> t
            }),
          ]),
        ])
      }),
    ),
  ])
}

fn view_page(model: Model) -> Element(Msg) {
  html.section([attribute.class("page")], [
    html.nav([attribute.class("page-nav")], [
      html.a(
        [attribute.class("back"), attribute.href(route.to_hash(PageList))],
        [
          html.text("← ページ一覧"),
        ],
      ),
      html.span(
        [attribute.class("peers")],
        list.map(model.peers, fn(p) {
          html.span(
            [attribute.class("peer"), attribute.style("--peer", p.color)],
            [html.text(p.name)],
          )
        }),
      ),
      html.span([attribute.class("status")], [html.text(model.status)]),
    ]),
    element.fragment(
      list.map(visible_blocks(model.blocks, model.collapsed), fn(b) {
        view_block(b, set.contains(model.collapsed, b.id))
      }),
    ),
  ])
}

/// 畳んだトグルの後ろにある、トグルより深いブロックを除く。
pub fn visible_blocks(
  blocks: List(Block),
  collapsed: Set(String),
) -> List(Block) {
  let #(_, shown) =
    list.fold(blocks, #(None, []), fn(acc, b) {
      let #(hide_deeper_than, shown) = acc
      case hide_deeper_than {
        Some(depth) if b.indent > depth -> acc
        _ -> {
          let hide = case b.kind == Toggle && set.contains(collapsed, b.id) {
            True -> Some(b.indent)
            False -> None
          }
          #(hide, [b, ..shown])
        }
      }
    })
  list.reverse(shown)
}

fn kind_label(kind: BlockKind) -> String {
  case kind {
    Paragraph -> "段落"
    Heading -> "見出し"
    Bulleted -> "箇条書き"
    Todo -> "ToDo"
    Code -> "コード"
    Quote -> "引用"
    Divider -> "区切り線"
    Toggle -> "トグル"
  }
}

fn view_block(b: Block, collapsed: Bool) -> Element(Msg) {
  let kind = block.kind_to_string(b.kind)
  let text_attrs = [
    attribute.id("block-" <> b.id),
    attribute.class("block-input"),
    attribute.value(b.text),
    event.on_input(fn(text) { TextEdited(b.id, text) }),
    on_block_key(b),
  ]
  let marker = case b.kind {
    Bulleted -> html.span([attribute.class("block-marker")], [html.text("•")])
    Todo ->
      html.input([
        attribute.type_("checkbox"),
        attribute.class("block-check"),
        attribute.checked(b.checked),
        attribute.aria_label("完了"),
        event.on_check(fn(checked) { CheckToggled(b.id, checked) }),
      ])
    Toggle ->
      html.button(
        [
          attribute.type_("button"),
          attribute.class("block-fold"),
          attribute.aria_expanded(!collapsed),
          attribute.aria_label("中身を開閉する"),
          event.on_click(CollapseToggled(b.id)),
        ],
        [
          html.text(case collapsed {
            True -> "▶"
            False -> "▼"
          }),
        ],
      )
    _ -> element.none()
  }
  let body = case b.kind {
    Divider -> html.hr([attribute.class("block-rule")])
    // コードは複数行。Enter は改行で、Ctrl+Enter で次のブロックへ
    Code ->
      html.textarea(
        [
          attribute.attribute("wrap", "off"),
          attribute.attribute("spellcheck", "false"),
          attribute.rows(list.length(string.split(b.text, "\n"))),
          ..text_attrs
        ],
        b.text,
      )
    _ -> html.input([attribute.type_("text"), ..text_attrs])
  }
  html.div(
    [
      attribute.class("block block-" <> kind),
      attribute.classes([#("is-checked", b.kind == Todo && b.checked)]),
      attribute.style("--indent", int.to_string(b.indent)),
    ],
    [
      marker,
      body,
      html.select(
        [
          attribute.class("block-kind"),
          attribute.aria_label("ブロックの種類"),
          event.on_change(fn(k) { KindChanged(b.id, k) }),
        ],
        list.map(block.kinds, fn(k) {
          html.option(
            [
              attribute.value(block.kind_to_string(k)),
              attribute.selected(k == b.kind),
            ],
            kind_label(k),
          )
        }),
      ),
      html.button(
        [
          attribute.type_("button"),
          attribute.class("block-delete"),
          attribute.title("ブロックを消す"),
          event.on_click(BlockDeleted(b.id)),
        ],
        [html.text("×")],
      ),
    ],
  )
}

/// ブロックの入力欄の keydown。Enter（コードでは Ctrl / Cmd + Enter）で次のブロック、
/// Tab / Shift+Tab で深さを変える。日本語入力の変換中（isComposing）と
/// ほかのキーは無視する（デコードを失敗させるとメッセージは出ない）。
fn on_block_key(b: Block) -> attribute.Attribute(Msg) {
  event.advanced("keydown", {
    use key <- decode.field("key", decode.string)
    use composing <- decode.optional_field("isComposing", False, decode.bool)
    use shift <- decode.optional_field("shiftKey", False, decode.bool)
    use ctrl <- decode.optional_field("ctrlKey", False, decode.bool)
    use meta <- decode.optional_field("metaKey", False, decode.bool)
    let msg = case key, composing {
      _, True -> Error(Nil)
      "Enter", False ->
        case b.kind != Code || ctrl || meta {
          True -> Ok(EnterPressed(b.id))
          False -> Error(Nil)
        }
      "Tab", False ->
        Ok(
          IndentPressed(b.id, case shift {
            True -> -1
            False -> 1
          }),
        )
      _, _ -> Error(Nil)
    }
    case msg {
      Ok(msg) ->
        decode.success(event.handler(
          dispatch: msg,
          prevent_default: True,
          stop_propagation: False,
        ))
      Error(Nil) ->
        decode.failure(
          event.handler(
            dispatch: BlockDeleted(""),
            prevent_default: False,
            stop_propagation: False,
          ),
          "key",
        )
    }
  })
}
