defmodule LangOS.Splitter do
  @moduledoc """
  Semantic unit splitter for long documents.

  Splits text into sentence-level units with byte spans into the original
  document, so every unit's IR mentions can be re-anchored to the source.
  Common abbreviations and decimal numbers do not end a unit.
  """

  @abbreviations ~w(mr mrs ms dr prof sr jr st vs etc eg ie no fig al inc ltd)

  @unit_regex ~r/\S[^.!?\n]*(?:[.!?]+|\n+|$)/u

  @type unit :: %{required(String.t()) => term()}

  @spec split(String.t()) :: [unit()]
  def split(text) when is_binary(text) do
    @unit_regex
    |> Regex.scan(text, return: :index)
    |> Enum.map(fn [{start, len}] -> {start, len} end)
    |> merge_false_boundaries(text)
    |> Enum.map(fn {start, len} ->
      %{
        "text" => text |> binary_part(start, len) |> String.trim(),
        "span" => [start, start + len]
      }
    end)
    |> Enum.reject(&(&1["text"] == ""))
  end

  # A period after an abbreviation ("Dr.") or inside a decimal number ("2.5")
  # does not end a unit: merge such a fragment with the one that follows it.
  defp merge_false_boundaries(spans, text) do
    spans
    |> Enum.reduce([], fn {start, len}, acc ->
      case acc do
        [{prev_start, prev_len} | rest] ->
          prev_fragment = binary_part(text, prev_start, prev_len)
          next_fragment = binary_part(text, start, len)

          if false_boundary?(prev_fragment, next_fragment) do
            [{prev_start, start + len - prev_start} | rest]
          else
            [{start, len} | acc]
          end

        [] ->
          [{start, len}]
      end
    end)
    |> Enum.reverse()
  end

  defp false_boundary?(fragment, next_fragment) do
    trimmed = String.trim_trailing(fragment)

    cond do
      not String.ends_with?(trimmed, ".") ->
        false

      # Decimal number split ("2." + "5 dollars"): only when the
      # continuation starts with a digit — "Biology A1." is a real end.
      Regex.match?(~r/\d\.$/, trimmed) ->
        Regex.match?(~r/^\d/, next_fragment)

      true ->
        last_word =
          trimmed
          |> String.trim_trailing(".")
          |> String.split(~r/\s+/)
          |> List.last()
          |> Kernel.||("")
          |> String.downcase()

        last_word in @abbreviations
    end
  end
end
