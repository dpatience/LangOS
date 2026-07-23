defmodule LangOS.Engine.Registry do
  @moduledoc """
  Discovers and selects LangOS inference engines from configuration.
  """
  use GenServer

  alias LangOS.Config
  alias LangOS.Engine.{Lexical, Neural, Rule, Stat, Syntax}

  @engines %{
    "rule" => Rule,
    "syntax" => Syntax,
    "lexical" => Lexical,
    "stat" => Stat,
    "neural" => Neural
  }

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec list() :: [map()]
  def list do
    GenServer.call(__MODULE__, :list)
  end

  @spec get(String.t()) :: {:ok, module()} | {:error, :not_found | :disabled}
  def get(id) when is_binary(id) do
    GenServer.call(__MODULE__, {:get, id})
  end

  @spec enabled?(String.t()) :: boolean()
  def enabled?(id), do: match?({:ok, _}, get(id))

  @impl true
  def init(_opts) do
    enabled =
      case Process.whereis(Config) do
        nil ->
          @engines
          |> Map.new(fn {id, mod} -> {id, mod} end)

        _ ->
          load_enabled()
      end

    {:ok, enabled}
  end

  @impl true
  def handle_call(:list, _from, state) do
    engines =
      Enum.map(state, fn {id, mod} ->
        %{
          id: id,
          capabilities: mod.capabilities(),
          health: health_to_string(mod.health())
        }
      end)

    {:reply, engines, state}
  end

  def handle_call({:get, id}, _from, state) do
    case Map.get(state, id) do
      nil -> {:reply, {:error, if(Map.has_key?(@engines, id), do: :disabled, else: :not_found)}, state}
      mod -> {:reply, {:ok, mod}, state}
    end
  end

  defp load_enabled do
    @engines
    |> Enum.filter(fn {id, _mod} ->
      Config.get([:engines, String.to_atom(id), :enabled], true)
    end)
    |> Map.new()
  end

  defp health_to_string(:ok), do: "ok"
  defp health_to_string({:error, reason}), do: "error: #{inspect(reason)}"
end
