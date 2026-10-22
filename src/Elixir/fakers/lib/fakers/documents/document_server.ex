defmodule Fakers.Documents.DocumentServer do
  @moduledoc """
  開いている文書 1 つにつき 1 プロセス。状態は yjs の update v1 のバイナリで持ち、
  マージは `Fakers.Native`（Rust の純関数）に任せる（ADR-0003）。

  - 名前は `{:via, Registry, {Fakers.Documents.Registry, id}}`。`Fakers.Documents.Supervisor`（DynamicSupervisor）の下で `restart: :transient`
  - 更新で `dirty` にし、`flush_ms` 後にまとめて DB に書く（debounce）。そのとき最初の見出しの文字列を `title` 列にも写す
  - `idle_ms` の間なにも来なければ flush して `:normal` で止まる
  - 状態の map に `:vsn` を持ち `code_change/3` を実装する。これがホットスワップの足場
  """
  use GenServer, restart: :transient
  require Logger
  import Ecto.Query, only: [from: 2]

  alias Fakers.Documents.Document
  alias Fakers.{Native, Repo}

  @vsn 1

  # ---------------------------------------------------------------- API

  def start_link(id), do: GenServer.start_link(__MODULE__, id, name: via(id))

  def via(id), do: {:via, Registry, {Fakers.Documents.Registry, id}}

  def whereis(id), do: GenServer.whereis(via(id))

  @spec get_state(String.t()) :: binary()
  def get_state(id), do: GenServer.call(via(id), :get_state)

  @spec apply_update(String.t(), binary()) :: :ok | {:error, String.t()}
  def apply_update(id, update) when is_binary(update),
    do: GenServer.call(via(id), {:apply_update, update})

  @doc "今すぐ DB に書く（テストと停止で使う）"
  def flush(id), do: GenServer.call(via(id), :flush)

  def stop(id), do: GenServer.stop(via(id), :normal)

  # ---------------------------------------------------------------- callbacks

  @impl true
  def init(id) do
    Process.flag(:trap_exit, true)

    case Repo.get(Document, id) do
      nil ->
        {:stop, :not_found}

      %Document{state: state} ->
        {:ok, %{vsn: @vsn, id: id, state: state, dirty: false, flush_timer: nil}, idle_ms()}
    end
  end

  @impl true
  def handle_call(:get_state, _from, s), do: {:reply, s.state, s, idle_ms()}

  def handle_call({:apply_update, update}, _from, s) do
    case Native.apply_update(s.state, update) do
      {:ok, new_state} ->
        {:reply, :ok, schedule_flush(%{s | state: new_state, dirty: true}), idle_ms()}

      {:error, reason} ->
        {:reply, {:error, reason}, s, idle_ms()}
    end
  end

  def handle_call(:flush, _from, s), do: {:reply, :ok, do_flush(s), idle_ms()}

  @impl true
  def handle_info(:flush, s), do: {:noreply, do_flush(%{s | flush_timer: nil}), idle_ms()}
  def handle_info(:timeout, s), do: {:stop, :normal, do_flush(s)}
  def handle_info(_other, s), do: {:noreply, s, idle_ms()}

  @impl true
  def terminate(_reason, s) do
    do_flush(s)
    :ok
  end

  @impl true
  def code_change(_old_vsn, s, _extra), do: {:ok, Map.put(s, :vsn, @vsn)}

  # ---------------------------------------------------------------- 内部

  defp schedule_flush(%{flush_timer: nil} = s),
    do: %{s | flush_timer: Process.send_after(self(), :flush, flush_ms())}

  defp schedule_flush(s), do: s

  defp do_flush(%{dirty: false} = s), do: s

  defp do_flush(s) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {1, _} =
      Repo.update_all(from(d in Document, where: d.id == ^s.id),
        set: [state: s.state, updated_at: now] ++ title_set(s.state)
      )

    %{s | dirty: false}
  rescue
    e ->
      # 書けなくても落とさない（次の flush か停止でもう一度試す）
      Logger.error("DocumentServer #{s.id}: flush に失敗 #{Exception.message(e)}")
      s
  end

  # 最初の見出しの文字列を title にする。見出しが無ければ title は変えない
  defp title_set(state) do
    with {:ok, json} <- Native.blocks_json(state),
         {:ok, blocks} <- :fakers_shared@block.decode_blocks(json),
         {:block, _, :heading, text} <- Enum.find(blocks, &match?({:block, _, :heading, _}, &1)) do
      [title: text]
    else
      _ -> []
    end
  end

  defp flush_ms, do: Keyword.fetch!(Application.fetch_env!(:fakers, Fakers.Documents), :flush_ms)
  defp idle_ms, do: Keyword.fetch!(Application.fetch_env!(:fakers, Fakers.Documents), :idle_ms)
end
