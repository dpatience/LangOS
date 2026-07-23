defmodule LangOS.LanguageDetector do
  @moduledoc """
  Detects which installed language pack should process the input.

  Detection layers:

    1. **Explicit hint** — a request with `locale: "tr"` bypasses detection.
    2. **Script identification** — non-Latin text (Arabic, Cyrillic, CJK,
       Devanagari, …) is matched to packs that declare the same `script`
       in grammar.json, narrowing candidates before lexical scoring.
    3. **Lexical scoring** — verb maps, pronoun maps, function words, and
       morphological stripping (prefix and suffix) score each candidate pack.
       The highest-scoring pack above `@min_score` wins.

  Works with any writing system because script ranges are Unicode-block based,
  not hard-coded character lists.
  """

  alias LangOS.{Grammar, Lexicon, LanguagePack}

  @word_regex ~r/[\p{L}\p{N}']+/u
  @min_score 0.2
  @default "en"

  @en_function_words ~w(
    the a an is are was were am be been being of and or to in on at for
    with this that it i you we they he she my your our their do does did
    can could will would shall should must what who where when why how
    not no yes please me him her us them
  )

  @script_ranges [
    {"arabic",     ~r/[\p{Arabic}]/u},
    {"cyrillic",   ~r/[\p{Cyrillic}]/u},
    {"cjk",        ~r/[\p{Han}]/u},
    {"hangul",     ~r/[\p{Hangul}]/u},
    {"devanagari", ~r/[\p{Devanagari}]/u},
    {"hiragana",   ~r/[\p{Hiragana}]/u},
    {"katakana",   ~r/[\p{Katakana}]/u},
    {"thai",       ~r/[\p{Thai}]/u},
    {"hebrew",     ~r/[\p{Hebrew}]/u},
    {"ethiopic",   ~r/[\p{Ethiopic}]/u},
    {"bengali",    ~r/[\p{Bengali}]/u},
    {"georgian",   ~r/[\p{Georgian}]/u},
    {"greek",      ~r/[\p{Greek}]/u},
    {"tamil",      ~r/[\p{Tamil}]/u},
    {"telugu",     ~r/[\p{Telugu}]/u},
    {"myanmar",    ~r/[\p{Myanmar}]/u}
  ]

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
        ids = installed_ids()

        # Narrow by script if the text uses a non-Latin writing system.
        candidates =
          case detect_script(text) do
            "latin" -> ids
            script ->
              matches = Enum.filter(ids, fn id -> Grammar.script(id) == script end)
              if matches == [], do: ids, else: matches
          end

        candidates
        |> Enum.map(fn id -> {id, score(id, tokens)} end)
        |> Enum.sort_by(fn {id, s} -> {-s, tie_break(id)} end)
        |> List.first()
        |> case do
          {id, s} when s >= @min_score -> id
          _ -> @default
        end
    end
  end

  @doc """
  Identify the dominant script in the text. Returns "latin" for Latin-based
  or mixed text, or a specific script name for non-Latin majority.
  """
  @spec detect_script(String.t()) :: String.t()
  def detect_script(text) do
    Enum.find_value(@script_ranges, "latin", fn {name, regex} ->
      if Regex.match?(regex, text), do: name
    end)
  end

  defp tokenize(text) do
    Regex.scan(@word_regex, String.downcase(text)) |> Enum.map(&hd/1)
  end

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
