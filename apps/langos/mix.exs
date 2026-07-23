defmodule LangOS.MixProject do
  use Mix.Project

  def project do
    [
      app: :langos,
      version: "0.1.0",
      escript: [main_module: LangOS.CLI, name: "patience"],
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.16",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases()
    ]
  end

  def application do
    [
      mod: {LangOS.Application, []},
      extra_applications: [:logger, :runtime_tools, :crypto]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:bandit, "~> 1.0"},
      {:jason, "~> 1.4"},
      {:plug, "~> 1.16"},
      {:cachex, "~> 4.0"},
      {:rustler, "~> 0.36", runtime: false},
      {:telemetry, "~> 1.3"},
      {:grpc, "~> 0.10"},
      # grpc's cowboy server adapter is an optional dep; depend on it
      # explicitly so ranch/cowboy start before our gRPC endpoint.
      {:cowboy, "~> 2.14"},
      {:protobuf, "~> 0.14"}
    ]
  end

  defp aliases do
    [
      "compile.rust": ["cmd cargo build --manifest-path ../../crates/langos_nif/Cargo.toml"],
      compile: ["compile.rust", "compile"]
    ]
  end
end
