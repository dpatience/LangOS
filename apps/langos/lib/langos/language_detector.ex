defmodule LangOS.LanguageDetector do
  @moduledoc """
  Stage 1 of the understanding pipeline: decide which language pack parses.

  Every installed pack contributes detection signals — its verb map, pronoun
  map, declared function words, and (for agglutinative languages such as
  Kinyarwanda) morphological prefix stripping so that an inflected form like
  "nshaka" (n- + shaka) still hits the pack's verb stem. English scores
  through its full lexicon plus closed-class function words.

  The winner's pack drives the rest of the pipeline, so a Kinyarwanda
  sentence is parsed by the Kinyarwanda pack — never by the English one.
  """

  alias LangOS.{Lexicon, LanguagePack}

  @word_regex ~r/[\p{L}\p{N}']+/u
  @min_score 0.2
  @default "en"

  @en_function_words ~w(
    the a an is are was were am be been being of and or to in on at for
    with this that it i you we they he she my your our their do does did
    can could will would shall should must what who where when why how
    not no yes please me him her us them
  )

  @spec detect(String.t(), String.t() | nil) :: String.t()
  def detect(text, hint \\ nil)

  def detect(_text, hint) when is_binary(hint) and hint != "" do
    hint |> String.downcase() |> String.split("-") |> hd()
  end

  def detect(text, _hint) do
    tokens = tokenize(text)

    case tokens do
      [] ->
        @default

      _ ->
        installed_ids()
        |> Enum.map(fn id -> {id, score(id, tokens)} end)
        |> Enum.sort_by(fn {id, score} -> {-score, tie_break(id)} end)
        |> List.first()
        |> case do
          {id, score} when score >= @min_score -> id
          _ -> @default
        end
    end
  end

  defp tokenize(text) do
    Regex.scan(@word_regex, String.downcase(text)) |> Enum.map(&hd/1)
  end

  # Default pack wins ties.
  defp tie_break(@default), do: 0
  defp tie_break(_), do: 1

  defp score(id, tokens) do
    hits = Enum.count(tokens, &token_hit?(id, &1))
    hits / length(tokens)
  end

  defp token_hit?("en", token) do
    token in @en_function_words or Lexicon.lookup(token, "en") != nil
  end

  defp token_hit?(id, token) do
    verb_map = LanguagePack.Registry.verb_map(id)
    pronoun_map = LanguagePack.Registry.pronoun_map(id)
    detection = LanguagePack.Registry.detection(id)
    words = Map.get(detection, "words", [])

    Map.has_key?(verb_map, token) or Map.has_key?(pronoun_map, token) or
      token in words or stripped_hit?(token, verb_map, detection)
  end

  # Morphological probe: strip declared prefixes and suffixes (longest first)
  # and re-check the verb map. Prefix languages (Kinyarwanda): "nshaka" ->
  # "shaka". Suffix languages (Turkish): "istiyorum" -> "ist".
  defp stripped_hit?(token, verb_map, detection) do
    prefix_hit =
      detection
      |> Map.get("strip_prefixes", [])
      |> Enum.sort_by(&(-String.length(&1)))
      |> Enum.any?(fn prefix ->
        rest = String.replace_prefix(token, prefix, "")
        rest != token and String.length(rest) > 1 and Map.has_key?(verb_map, rest)
      end)

    prefix_hit or
      detection
      |> Map.get("strip_suffixes", [])
      |> Enum.sort_by(&(-String.length(&1)))
      |> Enum.any?(fn suffix ->
        rest = String.replace_suffix(token, suffix, "")
        rest != token and String.length(rest) > 1 and Map.has_key?(verb_map, rest)
      end)
  end

  defp installed_ids do
    case Process.whereis(LanguagePack.Registry) do
      nil -> [@default]
      _ -> LanguagePack.Registry.installed_ids()
    end
  end
end
