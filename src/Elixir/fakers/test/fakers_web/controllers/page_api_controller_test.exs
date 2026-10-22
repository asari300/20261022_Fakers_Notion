defmodule FakersWeb.PageApiControllerTest do
  use FakersWeb.ConnCase, async: false

  test "ページを作って一覧に出る", %{conn: conn} do
    conn1 = post(conn, ~p"/api/pages", %{"title" => "API"})
    assert %{"id" => id, "title" => "API"} = json_response(conn1, 201)
    assert {:ok, _} = Ecto.UUID.cast(id)

    conn2 = get(conn, ~p"/api/pages")
    assert [%{"id" => ^id, "title" => "API"}] = json_response(conn2, 200)
  end

  test "title が無いか空なら 400 / 422", %{conn: conn} do
    assert %{"error" => _} = json_response(post(conn, ~p"/api/pages", %{}), 400)

    assert %{"errors" => %{"title" => _}} =
             json_response(post(conn, ~p"/api/pages", %{"title" => ""}), 422)
  end

  test "/ と /p/xxx は SPA の index.html を返す", %{conn: conn} do
    for path <- ["/", "/p/whatever"] do
      resp = get(conn, path)
      assert resp.status == 200
      assert resp.resp_body =~ ~s(<div id="app">)
      assert get_resp_header(resp, "content-type") |> hd() =~ "text/html"
    end
  end
end
