defmodule Fakers.DocumentsTest do
  use Fakers.DataCase, async: false

  alias Fakers.Documents
  alias Fakers.Documents.DocumentServer
  alias Fakers.Native

  setup do
    {:ok, doc} = Documents.create_page("テスト")
    on_exit(fn -> :ok end)
    %{doc: doc}
  end

  defp stop_if_alive(id) do
    if DocumentServer.whereis(id), do: DocumentServer.stop(id)
  end

  test "create_page は見出しと空の段落をシードし、一覧に出る", %{doc: doc} do
    assert [%{id: id, title: "テスト"}] = Documents.list_pages()
    assert id == doc.id
    assert {:ok, json} = Native.blocks_json(doc.state)

    assert {:ok, [{:block, _, :heading, "テスト"}, {:block, _, :paragraph, ""}]} =
             :fakers_shared@block.decode_blocks(json)

    assert Documents.get_page(doc.id).id == doc.id
    assert Documents.get_page("not-a-uuid") == nil
    assert Documents.get_page(Ecto.UUID.generate()) == nil
  end

  test "空の title は作れない" do
    assert {:error, %Ecto.Changeset{}} = Documents.create_page("")
  end

  test "ensure_server は冪等で、無いページは not_found", %{doc: doc} do
    assert {:ok, pid} = Documents.ensure_server(doc.id)
    assert {:ok, ^pid} = Documents.ensure_server(doc.id)
    assert {:error, :not_found} = Documents.ensure_server(Ecto.UUID.generate())
    stop_if_alive(doc.id)
  end

  test "update を適用し、flush で DB に残り、再起動後も残る", %{doc: doc} do
    {:ok, {_, update}} = Native.edit_text(doc.state, block_id(doc.state, 1), 0, "hello")
    assert :ok = Documents.apply_update(doc.id, update)
    {:ok, state} = Documents.document_state(doc.id)
    assert text(state, 1) == "hello"

    # debounce の前は DB は古いまま。flush で書かれる
    assert Documents.get_page(doc.id).state == doc.state
    :ok = DocumentServer.flush(doc.id)
    assert Documents.get_page(doc.id).state == state

    # 止めて起動し直しても同じ
    DocumentServer.stop(doc.id)
    refute DocumentServer.whereis(doc.id)
    {:ok, restored} = Documents.document_state(doc.id)
    assert text(restored, 1) == "hello"
    stop_if_alive(doc.id)
  end

  test "debounce のタイマーでも DB に書かれる", %{doc: doc} do
    {:ok, {_, update}} = Native.edit_text(doc.state, block_id(doc.state, 1), 0, "later")
    :ok = Documents.apply_update(doc.id, update)
    Process.sleep(80)
    assert text(Documents.get_page(doc.id).state, 1) == "later"
    stop_if_alive(doc.id)
  end

  test "壊れた update は {:error, _} で状態は変わらない", %{doc: doc} do
    assert {:error, _} = Documents.apply_update(doc.id, <<1, 2, 3>>)
    {:ok, state} = Documents.document_state(doc.id)
    assert state == doc.state
    stop_if_alive(doc.id)
  end

  defp block_id(state, index) do
    {:ok, json} = Native.blocks_json(state)
    {:ok, blocks} = :fakers_shared@block.decode_blocks(json)
    {:block, id, _, _} = Enum.at(blocks, index)
    id
  end

  defp text(state, index) do
    {:ok, json} = Native.blocks_json(state)
    {:ok, blocks} = :fakers_shared@block.decode_blocks(json)
    {:block, _, _, t} = Enum.at(blocks, index)
    t
  end
end
