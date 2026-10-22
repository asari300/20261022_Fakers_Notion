# Gleam の共有パッケージ（src/Gleam/fakers_shared）を `gleam build --target erlang` でビルドし、
# その ebin を code path に足す小さなコンパイラ（ADR-0004。mix_gleam は使わない）。
# Elixir からは `:fakers_shared@block.decode_blocks(json)` のように呼べる。
defmodule Mix.Tasks.Compile.GleamShared do
  use Mix.Task.Compiler

  @shared Path.expand("../../Gleam/fakers_shared", __DIR__)

  @impl true
  def run(_args) do
    case System.cmd("gleam", ["build", "--target", "erlang"], cd: @shared, stderr_to_stdout: true) do
      {_out, 0} ->
        @shared
        |> Path.join("build/dev/erlang/*/ebin")
        |> Path.wildcard()
        |> Enum.each(&Code.prepend_path/1)

        {:ok, []}

      {out, code} ->
        Mix.shell().error(out)

        {:error,
         [
           %Mix.Task.Compiler.Diagnostic{
             compiler_name: "gleam_shared",
             file: Path.join(@shared, "gleam.toml"),
             position: 0,
             message: "gleam build --target erlang が失敗した（終了コード #{code}）",
             severity: :error
           }
         ]}
    end
  end

  @impl true
  def clean do
    File.rm_rf(Path.join(@shared, "build"))
    :ok
  end
end

defmodule Fakers.MixProject do
  use Mix.Project

  def project do
    [
      app: :fakers,
      # Gleam の共有パッケージ（src/Gleam/fakers_shared）を先にビルドする（ADR-0004）
      compilers: [:gleam_shared] ++ Mix.compilers(),
      version: "0.1.0",
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      listeners: [Phoenix.CodeReloader]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Fakers.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.8.16"},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.13"},
      {:ecto_sqlite3, "~> 0.26"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.2.0"},
      {:bandit, "~> 1.5"},
      # Rust の NIF（src/Rust/crates/fakers_nif）。crate の rustler と同じ 0.38 系（ADR-0003）
      {:rustler, "~> 0.38.0", runtime: false}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      precommit: ["compile --warnings-as-errors", "deps.unlock --unused", "format", "test"]
    ]
  end
end
