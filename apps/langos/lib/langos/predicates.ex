defmodule LangOS.Predicates do
  @moduledoc """
  Semantic Vocabulary interface.
  Maps surface verbs to stable numeric vocabulary IDs.
  Applications depend on IDs (ACT_000005), never on symbols or surface verbs.
  """

  @unknown %{"id" => "UNK_000001", "symbol" => "UNKNOWN"}

  @spec lookup_verb(String.t(), String.t()) :: map()
  def lookup_verb(verb, locale \\ "en") do
    verb_map = LangOS.LanguagePack.Registry.verb_map(locale)

    case Map.get(verb_map, String.downcase(verb)) do
      %{"id" => _, "symbol" => _} = entry -> entry
      _ -> @unknown
    end
  end

  @spec lookup_pronoun(String.t(), String.t()) :: String.t() | nil
  def lookup_pronoun(word, locale \\ "en") do
    pronoun_map = LangOS.LanguagePack.Registry.pronoun_map(locale)
    Map.get(pronoun_map, String.downcase(word))
  end

  @spec unknown() :: map()
  def unknown, do: @unknown
end
