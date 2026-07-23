defmodule LangOS.Umbrella.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      version: "0.1.0",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      releases: releases()
    ]
  end

  def cli do
    [preferred_envs: [serve: :dev, test: :test]]
  end

  defp deps do
    []
  end

  defp aliases do
    [
      setup: ["deps.get", "cmd cargo build --manifest-path crates/langos_nif/Cargo.toml"],
      test: ["test"]
    ]
  end

  defp releases do
    [
      patience: [
        applications: [langos: :permanent],
        steps: [:assemble, :tar]
      ]
    ]
  end
end
