defmodule LangOS.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    port = read_http_port()

    children = [
      LangOS.Config,
      LangOS.Cache,
      LangOS.Engine.Registry,
      LangOS.LanguagePack.Registry,
      LangOS.Pipeline.Supervisor,
      {Bandit, plug: LangOS.API.Router, port: port}
    ]

    opts = [strategy: :one_for_one, name: LangOS.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp read_http_port do
    path = Application.get_env(:langos, :config_file, "config/dev.json") |> Path.expand()

    case File.read(path) do
      {:ok, body} ->
        body |> Jason.decode!() |> get_in(["server", "http", "port"]) || 9473

      _ ->
        9473
    end
  end
end
