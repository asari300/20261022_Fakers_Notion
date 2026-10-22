defmodule Fakers.Documents.Document do
  @moduledoc """
  ページ（ブロック文書）の 1 行。`state` は yjs の update v1 のバイト列（ADR-0003、ADR-0005）。
  `title` はページ一覧に出す名前。見出しブロックの文字とは P1 では同期しない（既知のギャップ）。
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: false}
  schema "documents" do
    field :title, :string
    field :state, :binary
    timestamps(type: :utc_datetime)
  end

  def changeset(document, attrs) do
    document
    |> cast(attrs, [:id, :title, :state])
    |> validate_required([:id, :title, :state])
    |> validate_length(:title, min: 1, max: 200)
  end
end
