defmodule LangOS.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    config = read_server_config()
    http_port = get_in(config, ["http", "port"]) || 9473

    children =
      [
        LangOS.Config,
        LangOS.Cache,
        LangOS.Engine.Registry,
        LangOS.LanguagePack.Registry,
        LangOS.Pipeline.Supervisor,
        {Bandit, plug: LangOS.API.Router, port: http_port}
      ] ++ grpc_children(config)

    opts = [strategy: :one_for_one, name: LangOS.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # gRPC transport is optional (config server.grpc.enabled, default port 9474).
  defp grpc_children(config) do
    if get_in(config, ["grpc", "enabled"]) do
      port = get_in(config, ["grpc", "port"]) || 9474
      [{GRPC.Server.Supervisor, endpoint: LangOS.GRPC.Endpoint, port: port, start_server: true}]
    else
      []
    end
  end

  defp read_server_config do
    path = Application.get_env(:langos, :config_file, "config/dev.json") |> Path.expand()

    case File.read(path) do
      {:ok, body} -> body |> Jason.decode!() |> Map.get("server", %{})
      _ -> %{}
    end
  end
end
