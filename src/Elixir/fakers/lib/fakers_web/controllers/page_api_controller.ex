defmodule FakersWeb.PageApiController do
  @moduledoc "`/api/pages`。SPA（src/Gleam/fakers_web）が使う。形は fakers_shared/page.gleam の `PageSummary`"
  use FakersWeb, :controller

  alias Fakers.Documents

  def index(conn, _params), do: json(conn, Documents.list_pages())

  def create(conn, %{"title" => title}) when is_binary(title) do
    case Documents.create_page(title) do
      {:ok, doc} ->
        conn |> put_status(:created) |> json(%{id: doc.id, title: doc.title})

      {:error, changeset} ->
        errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
        conn |> put_status(:unprocessable_entity) |> json(%{errors: errors})
    end
  end

  def create(conn, _params) do
    conn |> put_status(:bad_request) |> json(%{error: "title is required"})
  end
end
