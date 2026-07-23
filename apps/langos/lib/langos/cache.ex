defmodule LangOS.Cache do
  @moduledoc """
  L1 in-process request cache (Cachex).
  """
  use GenServer

  @table :langos_l1_cache

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec get(String.t()) :: {:ok, term()} | :miss
  def get(key) do
    case Cachex.get(@table, key) do
      {:ok, nil} -> :miss
      {:ok, value} -> {:ok, value}
      _ -> :miss
    end
  end

  @spec put(String.t(), term(), keyword()) :: :ok
  def put(key, value, opts \\ []) do
    ttl = Keyword.get(opts, :ttl, :timer.minutes(5))
    Cachex.put(@table, key, value, ttl: ttl)
    :ok
  end

  @spec cache_key(map()) :: String.t()
  def cache_key(%{} = request) do
    request
    |> Map.take(["text", "locale", "template", "options"])
    |> Jason.encode!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  @impl true
  def init(_opts) do
    {:ok, _} = Application.ensure_all_started(:cachex)

    case Cachex.start_link(name: @table, limit: 50_000) do
      {:ok, _} -> {:ok, %{}}
      {:error, {:already_started, _}} -> {:ok, %{}}
      other -> other
    end
  end
end
