defmodule FakersWeb.DocumentChannel do
  @moduledoc """
  `doc:<id>` の Channel。payload はすべてバイナリ（yjs の update v1）。

  - join: ページの存在を確かめ、文書のプロセスを起動し、購読が済んでから `"sync"` で全状態を push する
  - `"update"`: Rust でマージし、成功したらクライアントが送ったバイト列をそのまま他へ配る
    （全員が CRDT なので重複と順序の入れ替わりは無害。ADR-0003）
  """
  use FakersWeb, :channel

  alias Fakers.Documents

  @impl true
  def join("doc:" <> id, _payload, socket) do
    with %Documents.Document{} <- Documents.get_page(id),
         {:ok, _pid} <- Documents.ensure_server(id) do
      # topic の購読は join の後に行われるので、snapshot はその後に送る
      send(self(), :after_join)
      {:ok, assign(socket, :doc_id, id)}
    else
      _ -> {:error, %{reason: "not_found"}}
    end
  end

  @impl true
  def handle_info(:after_join, socket) do
    case Documents.document_state(socket.assigns.doc_id) do
      {:ok, state} -> push(socket, "sync", {:binary, state})
      {:error, _} -> push(socket, "error", %{reason: "not_found"})
    end

    {:noreply, socket}
  end

  @impl true
  def handle_in("update", {:binary, update}, socket) do
    case Documents.apply_update(socket.assigns.doc_id, update) do
      :ok ->
        broadcast_from!(socket, "update", {:binary, update})
        {:reply, :ok, socket}

      {:error, reason} ->
        {:reply, {:error, %{reason: to_string(reason)}}, socket}
    end
  end

  def handle_in("update", _payload, socket) do
    {:reply, {:error, %{reason: "binary payload expected"}}, socket}
  end
end
