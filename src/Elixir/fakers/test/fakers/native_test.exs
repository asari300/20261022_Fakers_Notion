defmodule Fakers.NativeTest do
  use ExUnit.Case, async: true

  alias Fakers.Native

  test "new_page → blocks_json → Gleam（fakers_shared）でデコードできる" do
    state = Native.new_page("T", "h1", "p1")
    assert is_binary(state) and byte_size(state) > 0
    assert {:ok, json} = Native.blocks_json(state)

    assert {:ok, [{:block, "h1", :heading, "T", false, 0}, {:block, "p1", :paragraph, "", false, 0}]} =
             :fakers_shared@block.decode_blocks(json)
  end

  test "edit_text の update を apply_update で適用できる" do
    state = Native.new_page("T", "h1", "p1")
    assert {:ok, {edited, update}} = Native.edit_text(state, "p1", 0, "こんにちは")
    assert {:ok, applied} = Native.apply_update(state, update)
    assert Native.blocks_json(applied) == Native.blocks_json(edited)
    assert {:ok, json} = Native.blocks_json(applied)

    assert {:ok, [_, {:block, "p1", :paragraph, "こんにちは", false, 0}]} =
             :fakers_shared@block.decode_blocks(json)
  end

  test "state_vector と diff で追いつける" do
    base = Native.new_page("T", "h1", "p1")
    {:ok, sv} = Native.state_vector(base)
    {:ok, {edited, _}} = Native.edit_text(base, "p1", 0, "x")
    {:ok, d} = Native.diff(edited, sv)
    {:ok, caught_up} = Native.apply_update(base, d)
    assert Native.blocks_json(caught_up) == Native.blocks_json(edited)
  end

  test "壊れた update は {:error, _}" do
    state = Native.new_page("T", "h1", "p1")
    assert {:error, msg} = Native.apply_update(state, <<255, 255, 255, 255>>)
    assert is_binary(msg)
    assert {:error, _} = Native.edit_text(state, "nope", 0, "x")
  end
end
