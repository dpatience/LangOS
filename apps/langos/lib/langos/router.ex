defmodule LangOS.Router do
  @moduledoc """
  Selects LangOS engines per pipeline stage. Never routes to external APIs.
  """
  alias LangOS.{Config, Engine, Native}

  @type stage :: atom()
  @type context :: map()

  @spec select_engine(stage(), context()) :: {:ok, module()} | {:error, :no_engine}
  def select_engine(stage, context) do
    id = engine_id(stage, context)
    chain = fallback_chain(id)

    Enum.reduce_while(chain, {:error, :no_engine}, fn engine_id, _acc ->
      case Engine.Registry.get(engine_id) do
        {:ok, mod} -> {:halt, {:ok, mod}}
        {:error, _} -> {:cont, {:error, :no_engine}}
      end
    end)
  end

  @doc """
  Ordered engine chain for the parse stage:
  rule (precise patterns) → stat (trained model) → neural (bootstrap fallback).
  The pipeline tries each in order until one succeeds.
  """
  @spec parse_chain(context()) :: [module()]
  def parse_chain(_context) do
    ["rule", "stat", "neural"]
    |> Enum.flat_map(fn id ->
      case Engine.Registry.get(id) do
        {:ok, mod} -> [mod]
        {:error, _} -> []
      end
    end)
  end

  defp engine_id(:parse, context) do
    token_count = Map.get(context, :token_count, 0)
    max_simple = Config.get([:routing, :simple_command_max_tokens], 12)

    if token_count <= max_simple and command_like?(Map.get(context, :text, "")) do
      Config.get([:routing, :simple_command_engine], "rule")
    else
      Config.get([:routing, :default_parse_engine], "neural")
    end
  end

  defp engine_id(:generate, _context) do
    Config.get([:routing, :default_generate_engine], "neural")
  end

  defp engine_id(:detect_language, _context) do
    "stat"
  end

  defp engine_id(_, _context) do
    Config.get([:routing, :fallback_engine], "rule")
  end

  defp fallback_chain(primary) do
    fallback = Config.get([:routing, :fallback_engine], "rule")
    Enum.uniq([primary, fallback, "rule"])
  end

  defp command_like?(text) do
    trimmed = String.trim(text)

    Regex.match?(~r/^(register|create|add|delete|assign|update|remove|install|show|list)\b/i, trimmed) or
      String.length(trimmed) < 80
  end

  @spec token_count(String.t()) :: non_neg_integer()
  def token_count(text), do: Native.safe_count_tokens(text)
end
