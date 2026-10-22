defmodule FakersWeb.DocumentChannelTest do
  use FakersWeb.ChannelCase, async: false

  alias Fakers.Documents
  alias Fakers.Documents.DocumentServer
  alias Fakers.Native

  setup do
    {:ok, doc} = Documents.create_page("Channel")
    {:ok, _, socket_a} = join_doc(doc.id)
    assert_push "sync", {:binary, state_a}
    assert state_a == doc.state
    %{doc: doc, socket_a: socket_a}
  end

  defp join_doc(id) do
    FakersWeb.UserSocket
    |> socket("user", %{})
    |> subscribe_and_join(FakersWeb.DocumentChannel, "doc:" <> id)
  end

  defp paragraph_text(state) do
    {:ok, json} = Native.blocks_json(state)
    {:ok, [_, {:block, _, :paragraph, t}]} = :fakers_shared@block.decode_blocks(json)
    t
  end

  test "A の update が B に配られ、A には返事が返る", %{doc: doc, socket_a: socket_a} do
    {:ok, _, _socket_b} = join_doc(doc.id)
    assert_push "sync", {:binary, _state_b}

    {:ok, {_, update}} = Native.edit_text(doc.state, paragraph_id(doc.state), 0, "hi")
    ref = push(socket_a, "update", {:binary, update})
    assert_reply ref, :ok

    # B の Channel が受けた broadcast は、テストプロセス（B の transport）に push される
    assert_push "update", {:binary, ^update}

    {:ok, state} = Documents.document_state(doc.id)
    assert paragraph_text(state) == "hi"
    DocumentServer.stop(doc.id)
  end

  test "flush 後に DB に残り、停止して再 join しても編集が残る", %{doc: doc, socket_a: socket_a} do
    {:ok, {_, update}} = Native.edit_text(doc.state, paragraph_id(doc.state), 0, "persist")
    ref = push(socket_a, "update", {:binary, update})
    assert_reply ref, :ok

    :ok = DocumentServer.flush(doc.id)
    assert paragraph_text(Documents.get_page(doc.id).state) == "persist"

    DocumentServer.stop(doc.id)
    {:ok, _, _socket} = join_doc(doc.id)
    assert_push "sync", {:binary, restored}
    assert paragraph_text(restored) == "persist"
    DocumentServer.stop(doc.id)
  end

  test "壊れた update は error の返事で、配られない", %{doc: doc, socket_a: socket_a} do
    ref = push(socket_a, "update", {:binary, <<9, 9, 9>>})
    assert_reply ref, :error, %{reason: reason}
    assert reason =~ "decode"
    refute_push "update", _
    ref2 = push(socket_a, "update", %{"not" => "binary"})
    assert_reply ref2, :error, %{reason: "binary payload expected"}
    DocumentServer.stop(doc.id)
  end

  test "無いページには join できない" do
    assert {:error, %{reason: "not_found"}} = join_doc(Ecto.UUID.generate())
    assert {:error, %{reason: "not_found"}} = join_doc("nope")
  end

  defp paragraph_id(state) do
    {:ok, json} = Native.blocks_json(state)
    {:ok, [_, {:block, id, :paragraph, _}]} = :fakers_shared@block.decode_blocks(json)
    id
  end
end
