defmodule Fakers.Native do
  @moduledoc """
  Rust のコア（`src/Rust/crates/fakers_core`）を Rustler の NIF で呼ぶ薄い安定ファサード。

  文書の状態は呼び出し側（`Fakers.Documents.DocumentServer`）が yjs の update v1 のバイナリで持ち、
  ここにある関数はすべて純関数。NIF モジュール自体はホットスワップの対象にしない（ADR-0003）。
  全部 dirty CPU scheduler で動く。
  """

  use Rustler,
    otp_app: :fakers,
    crate: "fakers_nif",
    # Mix プロジェクトのルートからの相対。workspace の target（src/Rust/target）を共有する
    path: "../../Rust/crates/fakers_nif",
    # cargo test と同じ dev プロファイルの成果物を使い、yrs を 1 回だけコンパイルする
    mode: if(Mix.env() == :prod, do: :release, else: :debug)

  @type state :: binary()
  @type update :: binary()

  @doc "新しいページの初期状態（見出し = title、空の段落）"
  @spec new_page(String.t(), String.t(), String.t()) :: state()
  def new_page(_title, _heading_id, _para_id), do: :erlang.nif_error(:nif_not_loaded)

  @doc "状態に update を適用し、新しい全状態を返す"
  @spec apply_update(state(), update()) :: {:ok, state()} | {:error, String.t()}
  def apply_update(_state, _update), do: :erlang.nif_error(:nif_not_loaded)

  @spec state_vector(state()) :: {:ok, binary()} | {:error, String.t()}
  def state_vector(_state), do: :erlang.nif_error(:nif_not_loaded)

  @doc "state vector `sv` を持つ相手に送る差分"
  @spec diff(state(), binary()) :: {:ok, update()} | {:error, String.t()}
  def diff(_state, _sv), do: :erlang.nif_error(:nif_not_loaded)

  @doc ~S|ブロックの一覧を JSON（`[{"id","type","text"}]`）で|
  @spec blocks_json(state()) :: {:ok, String.t()} | {:error, String.t()}
  def blocks_json(_state), do: :erlang.nif_error(:nif_not_loaded)

  @doc "ブロックの文字列の UTF-16 位置に挿入する。{新しい全状態, この編集の update}"
  @spec edit_text(state(), String.t(), non_neg_integer(), String.t()) ::
          {:ok, {state(), update()}} | {:error, String.t()}
  def edit_text(_state, _block_id, _utf16_index, _insert), do: :erlang.nif_error(:nif_not_loaded)
end
