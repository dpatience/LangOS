defmodule LangOS.Parser.Pattern do
  @moduledoc """
  Pure Elixir command pattern matcher (fallback when Rust NIF unavailable).
  Emits vocab_id + symbol, per-argument spans for mentions.
  """

  @spec match(String.t(), String.t()) :: {:ok, map()} | {:ok, nil}
  def match(text, rules_json) do
    with {:ok, rules} <- Jason.decode(rules_json),
         patterns when is_list(patterns) <- rules["patterns"] do
      normalized = text |> String.trim() |> String.trim_trailing(".")

      case Enum.find_value(patterns, fn rule -> try_rule(rule, normalized) end) do
        nil -> {:ok, nil}
        match -> {:ok, match}
      end
    else
      _ -> {:ok, nil}
    end
  end

  defp try_rule(rule, text) do
    pattern = rule["pattern"]

    case Regex.run(~r/^#{pattern}$/iu, text, capture: :all, return: :index) do
      nil ->
        nil

      captures_idx ->
        full_text_captures = Regex.run(~r/^#{pattern}$/iu, text, capture: :all) || []

        arguments =
          (rule["groups"] || [])
          |> Enum.map(fn group ->
            idx = group["index"]
            label = Enum.at(full_text_captures, idx, "") |> String.trim()
            {start, len} = Enum.at(captures_idx, idx, {0, 0})

            %{
              "role" => group["role"],
              "kind" => group["kind"] || "named",
              "label" => label,
              "span" => [start, start + len]
            }
          end)

        %{
          "rule_id" => rule["id"],
          "vocab_id" => rule["vocab_id"],
          "symbol" => rule["symbol"],
          "unit_type" => rule["unit_type"] || "command",
          "arguments" => arguments,
          "span" => [0, String.length(text)],
          "confidence" => 0.97
        }
    end
  end
end
