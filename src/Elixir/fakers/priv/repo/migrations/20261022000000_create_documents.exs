defmodule Fakers.Repo.Migrations.CreateDocuments do
  use Ecto.Migration

  def change do
    create table(:documents, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string, null: false
      # yjs の update v1 のバイト列（文書の全状態）
      add :state, :binary, null: false
      timestamps(type: :utc_datetime)
    end
  end
end
