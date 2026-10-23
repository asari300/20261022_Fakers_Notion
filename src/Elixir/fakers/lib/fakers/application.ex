defmodule Fakers.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      FakersWeb.Telemetry,
      Fakers.Repo,
      {Ecto.Migrator,
       repos: Application.fetch_env!(:fakers, :ecto_repos), skip: skip_migrations?()},
      {DNSCluster, query: Application.get_env(:fakers, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Fakers.PubSub},
      FakersWeb.Presence,
      # 文書ごとのプロセス（Fakers.Documents.DocumentServer）の名前解決と監視
      {Registry, keys: :unique, name: Fakers.Documents.Registry},
      {DynamicSupervisor, name: Fakers.Documents.Supervisor, strategy: :one_for_one},
      # Start to serve requests, typically the last entry
      FakersWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Fakers.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    FakersWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp skip_migrations?() do
    # By default, sqlite migrations are run when using a release
    System.get_env("RELEASE_NAME") == nil
  end
end
