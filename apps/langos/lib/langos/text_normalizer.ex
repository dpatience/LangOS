defmodule LangOS.TextNormalizer do
  @moduledoc """
  Pre-processing that runs before language detection and parsing.

  Three responsibilities:

  1. **Missing-space repair** — "benfutball oynuyorum" → "ben futball oynuyorum".
     Works by scanning each token against the pack's word lists and the English
     lexicon. If a token is not found but a split of it produces two known words,
     the space is restored. Applies only when the result is unambiguous (exactly
     one valid split point).

  2. **Punctuation-only utterance_type signal** — strips and returns the terminal
     punctuation so the pipeline can apply it as an override after parsing.
     "We are in group 4?" has the same semantic graph as "We are in group 4."
     but `utterance_type` differs. The normalizer preserves the original
     punctuation and the caller applies it.

  3. **Whitespace cleanup** — collapses repeated spaces, normalizes newlines
     inside a single unit so the tokenizer never sees an empty first token.
  """

  alias LangOS.{Lexicon, LanguagePack}

  @terminal_punctuation ~r/[.!?]+\s*$/

  @spec normalize(String.t(), String.t()) :: %{
          text: String.t(),
          terminal_punct: String.t() | nil
        }
  def normalize(text, locale \\ "en") when is_binary(text) do
    text =
      text
      |> String.trim()
      |> String.replace(~r/\r\n|\r/, "\n")
      |> String.replace(~r/ {2,}/, " ")

    # Extract and remember the terminal punctuation before we touch anything.
    terminal_punct =
      case Regex.run(@terminal_punctuation, text) do
        [match] -> String.trim(match)
        _ -> nil
      end

    text = repair_missing_spaces(text, locale)

    %{text: text, terminal_punct: terminal_punct}
  end

  # ---- missing-space repair --------------------------------------------------

  defp repair_missing_spaces(text, locale) do
    word_regex = ~r/[\p{L}\p{N}']+/u

    Regex.scan(word_regex, text, return: :index)
    |> Enum.map_reduce(0, fn [{start, len}], acc ->
      gap = binary_part(text, acc, start - acc)
      token = binary_part(text, start, len)
      repaired = maybe_split_token(token, locale)
      {gap <> repaired, start + len}
    end)
    |> case do
      {parts, last_end} ->
        trailing = binary_part(text, last_end, byte_size(text) - last_end)
        IO.iodata_to_binary([parts, trailing])
    end
  end

  # Try all split points inside the token. Accept the split only if BOTH halves
  # are known words and the split is unique (ambiguous splits are left alone).
  defp maybe_split_token(token, _locale) when byte_size(token) < 4, do: token

  defp maybe_split_token(token, locale) do
    lower = String.downcase(token)

    if known_word?(lower, locale) do
      token
    else
      len = String.length(lower)

      candidates =
        for i <- 1..(len - 1),
            left = String.slice(lower, 0, i),
            right = String.slice(lower, i, len - i),
            String.length(left) >= 2,
            String.length(right) >= 2,
            known_word?(left, locale),
            known_word?(right, locale) do
          {i, left, right}
        end

      case candidates do
        [{_, left, right}] ->
          left_surface = String.slice(token, 0, String.length(left))
          right_surface = String.slice(token, String.length(left), String.length(right))
          left_surface <> " " <> right_surface

        _ ->
          token
      end
    end
  end

  defp known_word?(word, locale) do
    english_word?(word) or pack_word?(word, locale)
  end

  @en_function_words ~w(
    i me my mine myself we us our ours ourselves
    you your yours yourself yourselves
    he him his himself she her hers herself
    it its itself they them their theirs themselves
    the a an this that these those
    is am are was were be been being
    have has had do does did
    will would shall should can could may might must
    and or but nor for yet so
    of in on at to for with from by about as into
    through during before after above below
    up down out off over under again further
    no not never very just also only both
    all any each every few more most other some such
    than then here there when where why how
    what who which whose whom
    yes please thank
  )

  defp english_word?(word) do
    Lexicon.lookup(word, "en") != nil or word in @en_function_words
  end

  defp pack_word?(word, locale) when locale != "en" do
    vm = LanguagePack.Registry.verb_map(locale)
    pm = LanguagePack.Registry.pronoun_map(locale)
    dw = LanguagePack.Registry.detection(locale) |> Map.get("words", [])
    Map.has_key?(vm, word) or Map.has_key?(pm, word) or word in dw
  end

  defp pack_word?(_word, _locale), do: false
end
