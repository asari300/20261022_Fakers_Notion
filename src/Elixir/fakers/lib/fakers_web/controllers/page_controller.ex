defmodule FakersWeb.PageController do
  @moduledoc "SPA の入口。`priv/static/index.html` をそのまま返す（ルーティングはクライアントのハッシュ）"
  use FakersWeb, :controller

  def index(conn, _params) do
    conn
    |> put_resp_content_type("text/html")
    |> send_file(200, Application.app_dir(:fakers, "priv/static/index.html"))
  end
end
