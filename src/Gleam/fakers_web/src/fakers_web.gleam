//// Fakers Notion の SPA。ページ一覧とページ（ブロックの編集）の 2 画面。
//// update は純粋に保ち、セッションの操作はすべて effect.from の中で行う。

import fakers_shared/block.{type Block, Block, Heading, Paragraph}
import fakers_shared/page.{type PageSummary}
import fakers_web/api
import fakers_web/route.{type Route, PageList, PageView}
import fakers_web/session.{type Session}
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
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
  KindToggled(block_id: String, kind: block.BlockKind)
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

    EnterPressed(id) -> #(
      model,
      with_session(model, fn(s) {
        let new_id = session.insert_block_after(s, id, "paragraph")
        session.focus_block(new_id)
      }),
    )

    KindToggled(id, kind) -> #(
      model,
      with_session(model, fn(s) {
        session.set_kind(s, id, block.kind_to_string(kind))
      }),
    )

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
    element.fragment(list.map(model.blocks, view_block)),
  ])
}

fn view_block(b: Block) -> Element(Msg) {
  let #(kind_class, toggle_label, toggle_to, toggle_title) = case b.kind {
    Heading -> #("block-heading", "¶", Paragraph, "段落にする")
    Paragraph -> #("block-paragraph", "H", Heading, "見出しにする")
  }
  html.div([attribute.class("block " <> kind_class)], [
    html.input([
      attribute.type_("text"),
      attribute.id("block-" <> b.id),
      attribute.class("block-input"),
      attribute.value(b.text),
      event.on_input(fn(text) { TextEdited(b.id, text) }),
      on_enter(EnterPressed(b.id)),
    ]),
    html.button(
      [
        attribute.type_("button"),
        attribute.class("block-toggle"),
        attribute.title(toggle_title),
        event.on_click(KindToggled(b.id, toggle_to)),
      ],
      [html.text(toggle_label)],
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
  ])
}

/// keydown の Enter だけを拾う。日本語入力の変換確定の Enter（isComposing）と
/// ほかのキーは無視する（デコードを失敗させるとメッセージは出ない）。
fn on_enter(msg: Msg) -> attribute.Attribute(Msg) {
  event.advanced("keydown", {
    use key <- decode.field("key", decode.string)
    use composing <- decode.optional_field("isComposing", False, decode.bool)
    case key, composing {
      "Enter", False ->
        decode.success(event.handler(
          dispatch: msg,
          prevent_default: True,
          stop_propagation: False,
        ))
      _, _ ->
        decode.failure(
          event.handler(
            dispatch: msg,
            prevent_default: False,
            stop_propagation: False,
          ),
          "Enter",
        )
    }
  })
}
