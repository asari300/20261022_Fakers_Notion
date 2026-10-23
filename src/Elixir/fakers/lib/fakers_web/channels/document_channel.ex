defmodule FakersWeb.DocumentChannel do
  @moduledoc """
  `doc:<id>` の Channel。payload はすべてバイナリ（yjs の update v1）。

  - join: ページの存在を確かめ、文書のプロセスを起動し、購読が済んでから `"sync"` で全状態を push する
  - `"update"`: Rust でマージし、成功したらクライアントが送ったバイト列をそのまま他へ配る
    （全員が CRDT なので重複と順序の入れ替わりは無害。ADR-0003）
  - Presence: join ごとにサーバが user_id を振り、`"cursor"` で自分のカーソルを meta に載せる
  """
  use FakersWeb, :channel

  alias Fakers.Documents
  alias FakersWeb.Presence

  @max_name 32
  @max_id 64
  @max_pos 256

  @impl true
  def join("doc:" <> id, payload, socket) do
    with %Documents.Document{} <- Documents.get_page(id),
         {:ok, _pid} <- Documents.ensure_server(id) do
      # topic の購読は join の後に行われるので、snapshot はその後に送る
      send(self(), :after_join)
      user_id = Ecto.UUID.generate()

      socket =
        assign(socket, doc_id: id, user_id: user_id, name: clean_name(payload["name"]))

      {:ok, %{user_id: user_id}, socket}
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

    {:ok, _} =
      Presence.track(socket, socket.assigns.user_id, %{name: socket.assigns.name, cursor: nil})

    push(socket, "presence_state", Presence.list(socket))
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

  # %{} はカーソルを消す（フォーカスが外れた）
  def handle_in("cursor", payload, socket) do
    case clean_cursor(payload) do
      {:ok, cursor} ->
        {:ok, _} =
          Presence.update(socket, socket.assigns.user_id, &Map.put(&1, :cursor, cursor))

        {:reply, :ok, socket}

      :error ->
        {:reply, {:error, %{reason: "bad cursor"}}, socket}
    end
  end

  defp clean_cursor(%{"block" => b, "anchor" => a, "head" => h})
       when is_binary(b) and byte_size(b) <= @max_id and is_binary(a) and
              byte_size(a) <= @max_pos and is_binary(h) and byte_size(h) <= @max_pos,
       do: {:ok, %{block: b, anchor: a, head: h}}

  defp clean_cursor(payload) when payload == %{}, do: {:ok, nil}
  defp clean_cursor(_), do: :error

  defp clean_name(name) when is_binary(name) do
    case name |> String.trim() |> String.slice(0, @max_name) do
      "" -> "ゲスト"
      n -> n
    end
  end

  defp clean_name(_), do: "ゲスト"
end
