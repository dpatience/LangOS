defmodule LangOS.SDK.MixProject do
  use Mix.Project

  def project do
    [
      app: :langos_sdk,
      version: "0.1.0",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package()
    ]
  end

  def application do
    [extra_applications: [:logger, :inets, :ssl]]
  end

  defp deps do
    [{:jason, "~> 1.4"}]
  end

  defp package do
    [
      name: "langos_sdk",
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/langos/langos"}
    ]
  end
end
