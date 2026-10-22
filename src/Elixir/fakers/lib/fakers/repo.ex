defmodule Fakers.Repo do
  use Ecto.Repo,
    otp_app: :fakers,
    adapter: Ecto.Adapters.SQLite3
end
