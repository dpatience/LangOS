defmodule LangOS.Lexicon do
  @moduledoc """
  Fast lexicon index: every word LangOS understands, mapped to vocabulary IDs.

  Performance design:
  - The lexicon is loaded once per language into `:persistent_term`:
    lock-free, zero-copy reads shared across all processes.
  - `lookup/2` is a single hash-map fetch — O(1) regardless of lexicon size.
  - `annotate/2` scans a sentence with greedy longest-match: at each token it
    tries the longest possible phrase window first (bounded by the longest
    phrase in the lexicon). Complexity O(n * k) where n = token count and
    k = max phrase words (small constant), independent of lexicon size.
  """

  @word_regex ~r/[\p{L}\p{N}']+/u

  @spec lookup(String.t(), String.t()) :: map() | nil
  def lookup(word, locale \\ "en") do
    {entries, _max} = table(locale)
    Map.get(entries, String.downcase(word))
  end

  @doc """
  Scan text and return every lexicon match with surface and span.
  Longest phrases win over their prefixes ("sign up" beats "sign").
  """
  @spec annotate(String.t(), String.t()) :: [map()]
  def annotate(text, locale \\ "en") do
    {entries, max_words} = table(locale)
    scan(tokenize_with_spans(text), entries, max_words, [])
  end

  @doc """
  Word-level scan: matches single words only, never phrases.
  Used for reference extraction, where a pronoun must be found even
  when it sits inside a known phrase ("you" inside "do you know").
  """
  @spec annotate_words(String.t(), String.t()) :: [map()]
  def annotate_words(text, locale \\ "en") do
    {entries, _max} = table(locale)
    scan(tokenize_with_spans(text), entries, 1, [])
  end

  defp tokenize_with_spans(text) do
    Regex.scan(@word_regex, text, return: :index)
    |> Enum.map(fn [{start, len}] ->
      surface = binary_part(text, start, len)
      {String.downcase(surface), surface, start, start + len}
    end)
  end

  @spec entry_count(String.t()) :: non_neg_integer()
  def entry_count(locale \\ "en") do
    {entries, _} = table(locale)
    map_size(entries)
  end

  defp scan([], _entries, _max, acc), do: Enum.reverse(acc)

  defp scan([_ | rest] = tokens, entries, max_words, acc) do
    window = Enum.take(tokens, max_words)

    case best_match(window, entries) do
      {entry, consumed, surface, span} ->
        match = %{"entry" => entry, "surface" => surface, "span" => span}
        scan(Enum.drop(tokens, consumed), entries, max_words, [match | acc])

      nil ->
        scan(rest, entries, max_words, acc)
    end
  end

  defp best_match(window, entries) do
    # longest window first: greedy longest-match
    Enum.reduce_while(length(window)..1//-1, nil, fn size, _ ->
      candidate = Enum.take(window, size)
      key = candidate |> Enum.map(&elem(&1, 0)) |> Enum.join(" ")

      case Map.get(entries, key) do
        nil ->
          {:cont, nil}

        entry ->
          {_, first_surface, start, _} = List.first(candidate)
          {_, _, _, last_end} = List.last(candidate)

          surface =
            if size == 1, do: first_surface, else: key

          {:halt, {entry, size, surface, [start, last_end]}}
      end
    end)
  end

  defp table(locale) do
    key = {:langos_lexicon, locale}

    case :persistent_term.get(key, nil) do
      nil ->
        loaded = load(locale)
        :persistent_term.put(key, loaded)
        loaded

      loaded ->
        loaded
    end
  end

  defp load(locale) do
    path = resolve_path(Path.join(["packs", locale, "lexicon.json"]))

    with true <- is_binary(path),
         {:ok, body} <- File.read(path),
         {:ok, %{"entries" => entries} = doc} <- Jason.decode(body) do
      {entries, doc["max_phrase_words"] || 3}
    else
      _ -> {%{}, 1}
    end
  end

  defp resolve_path(relative) do
    candidates = [
      Path.expand(relative, File.cwd!()),
      Path.expand(Path.join("../../../..", relative), __DIR__)
    ]

    Enum.find(candidates, &File.exists?/1)
  end
end
