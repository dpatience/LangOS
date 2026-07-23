defmodule LangOS.Config do
  @moduledoc """
  Loads and provides access to LangOS JSON configuration.
  """
  use GenServer

  @name __MODULE__

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: @name)
  end

  def load! do
    case Process.whereis(@name) do
      nil -> start_link([])
      _ -> :ok
    end

    GenServer.call(@name, :get)
  end

  def get(path, default \\ nil) when is_list(path) do
    ensure_started()
    GenServer.call(@name, {:get, path, default})
  end

  @impl true
  def init(_opts) do
    path = config_path()

    config =
      case File.read(path) do
        {:ok, body} -> Jason.decode!(body)
        {:error, reason} -> raise "failed to read config #{path}: #{inspect(reason)}"
      end

    {:ok, %{config: config, path: path}}
  end

  @impl true
  def handle_call(:get, _from, state), do: {:reply, state.config, state}

  def handle_call({:get, path, default}, _from, %{config: config} = state) do
    {:reply, get_in(config, stringify_keys(path)) || default, state}
  end

  defp config_path do
    Application.get_env(:langos, :config_file) ||
      Path.join(Path.expand("../..", __DIR__), "config/dev.json")
  end

  defp stringify_keys(path) do
    Enum.map(path, fn
      key when is_atom(key) -> Atom.to_string(key)
      key -> key
    end)
  end

  defp ensure_started do
    case Process.whereis(@name) do
      nil ->
        {:ok, _} = start_link([])
        :ok

      _ ->
        :ok
    end
  end
end
