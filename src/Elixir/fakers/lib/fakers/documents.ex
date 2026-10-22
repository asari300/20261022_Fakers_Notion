defmodule Fakers.Documents do
  @moduledoc """
  ページ（ブロック文書）のコンテキスト。作成と一覧は DB、開いている文書の状態は
  `Fakers.Documents.DocumentServer`（文書ごとの GenServer）が持つ（doc/architecture.md の 3 と 6）。
  """
  import Ecto.Query, only: [from: 2]

  alias Fakers.Documents.{Document, DocumentServer}
  alias Fakers.{Native, Repo}

  @doc "ページの一覧（新しい順）。`%{id, title}` のリスト"
  @spec list_pages() :: [%{id: String.t(), title: String.t()}]
  def list_pages do
    Repo.all(
      from d in Document,
        order_by: [desc: d.inserted_at, desc: d.id],
        select: %{id: d.id, title: d.title}
    )
  end

  @doc "ページを取る。無ければ nil。UUID でない id も nil"
  @spec get_page(String.t()) :: Document.t() | nil
  def get_page(id) when is_binary(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> Repo.get(Document, uuid)
      :error -> nil
    end
  end

  @doc """
  ページを作る。初期状態は Rust（`Native.new_page`）がシードする: 見出し（title）と空の段落。
  サーバがシードするので、クライアントが最初のブロック作成で競合しない。
  """
  @spec create_page(String.t()) :: {:ok, Document.t()} | {:error, Ecto.Changeset.t()}
  def create_page(title) when is_binary(title) do
    id = Ecto.UUID.generate()
    state = Native.new_page(title, Ecto.UUID.generate(), Ecto.UUID.generate())

    %Document{}
    |> Document.changeset(%{id: id, title: title, state: state})
    |> Repo.insert()
  end

  @doc "文書のプロセスを起動する（起動済みなら成功扱い）。ページが無ければ `{:error, :not_found}`"
  @spec ensure_server(String.t()) :: {:ok, pid()} | {:error, term()}
  def ensure_server(id) when is_binary(id) do
    case DynamicSupervisor.start_child(Fakers.Documents.Supervisor, {DocumentServer, id}) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "文書の全状態（update v1）。プロセスが無ければ起動する"
  @spec document_state(String.t()) :: {:ok, binary()} | {:error, term()}
  def document_state(id) do
    with {:ok, _pid} <- ensure_server(id), do: {:ok, DocumentServer.get_state(id)}
  end

  @doc "update を文書に適用する。プロセスが無ければ起動する"
  @spec apply_update(String.t(), binary()) :: :ok | {:error, term()}
  def apply_update(id, update) when is_binary(update) do
    with {:ok, _pid} <- ensure_server(id), do: DocumentServer.apply_update(id, update)
  end
end
