defmodule LangOS.Grammar do
  @moduledoc """
  Generic grammar interpreter for any language pack.

  All language-specific knowledge lives in `packs/<id>/grammar.json`.
  This module reads those declarative rules and interprets them — it never
  hard-codes behaviour for a specific language. Adding a new language is
  adding a folder; no Elixir code changes.

  grammar.json teaches LangOS the 8 parts of speech for each language:

    1. **Nouns** — articles, gender system, plural rules, field_nouns
       lexicon for translating machine field names into human language
    2. **Pronouns** — personal pronouns in all cases (subject, object,
       possessive, reflexive, dative) with person keys for conjugation
    3. **Verbs** — imperative, statement, gerund, infinitive forms per
       semantic symbol; conjugation type (lexical/prefix/suffix)
    4. **Adjectives** — placement (before/after noun), agreement rules
       (none, gender, gender_case, noun_class), comparative/superlative
    5. **Adverbs** — placement rules, common adverbs including
       intensifiers, negation, and politeness markers
    6. **Prepositions** — semantic role → surface word mappings
       (or postpositions for SOV languages like Turkish)
    7. **Conjunctions** — coordinating (and/or/but) and subordinating
       (because/if/when) for building complex sentences
    8. **Interjections** — greetings, farewells, surprise, agreement,
       disagreement, hesitation, apology, encouragement, frustration

  Plus structural rules:
    * `script` — writing system ("latin", "cyrillic", "arabic", "cjk", …)
    * `word_order` — clause structure: "SVO", "SOV", "VSO"
    * `morphology` — type, conjugation system, vowel harmony tables
    * `elision` — phonological contractions
    * `possessive` — ownership expression pattern
    * `intents` — communicative-intent recipes the Realizer composes
  """

  alias LangOS.LanguagePack

  # ---- grammar loading -------------------------------------------------------

  @spec get(String.t()) :: map()
  def get(locale) do
    key = {:langos_grammar, locale}

    case :persistent_term.get(key, :missing) do
      :missing ->
        grammar = load(locale)
        :persistent_term.put(key, grammar)
        grammar

      grammar ->
        grammar
    end
  end

  @spec reload(String.t()) :: :ok
  def reload(locale) do
    :persistent_term.put({:langos_grammar, locale}, load(locale))
    :ok
  end

  defp load(locale) do
    with {:ok, pack} <- LanguagePack.Registry.get(locale),
         {:ok, body} <- File.read(Path.join(pack.root, "grammar.json")),
         {:ok, data} <- Jason.decode(body) do
      data
    else
      _ -> %{}
    end
  end

  @spec available?(String.t()) :: boolean()
  def available?(locale), do: get(locale) != %{}

  # ---- structural accessors ---------------------------------------------------

  @spec word_order(String.t()) :: String.t()
  def word_order(locale), do: get_in(get(locale), ["word_order"]) || "SVO"

  @spec script(String.t()) :: String.t()
  def script(locale), do: get_in(get(locale), ["script"]) || "latin"

  @spec morphology(String.t()) :: map()
  def morphology(locale), do: get_in(get(locale), ["morphology"]) || %{}

  @spec conjugation_type(String.t()) :: String.t()
  def conjugation_type(locale), do: get_in(morphology(locale), ["conjugation"]) || "lexical"

  @spec sentence_rules(String.t()) :: map()
  def sentence_rules(locale), do: get_in(get(locale), ["sentence_rules"]) || %{}

  @spec elision_rules(String.t()) :: [map()]
  def elision_rules(locale), do: get_in(get(locale), ["elision"]) || []

  # ---- list grammar -----------------------------------------------------------

  @spec list_join([String.t()], String.t(), String.t()) :: String.t()
  def list_join(items, locale, kind \\ "and")
  def list_join([], _locale, _kind), do: ""
  def list_join([only], _locale, _kind), do: only

  def list_join(items, locale, kind) do
    grammar = get(locale)
    conj = get_in(grammar, ["list", kind]) || default_conj(kind)
    oxford = get_in(grammar, ["list", "oxford"]) == true
    elide = get_in(grammar, ["list", "elide_before_vowel"])

    {rest, [last]} = Enum.split(items, length(items) - 1)
    joined_rest = Enum.join(rest, ", ")

    connective =
      cond do
        elide && starts_with_vowel?(last) -> elide <> last
        true -> conj <> " " <> last
      end

    if oxford and length(items) > 2 do
      joined_rest <> ", " <> connective
    else
      joined_rest <> " " <> connective
    end
  end

  defp default_conj("or"), do: "or"
  defp default_conj(_), do: "and"

  @doc "Unicode-aware vowel check covering Latin, Cyrillic, Turkish, and more."
  @spec starts_with_vowel?(String.t()) :: boolean()
  def starts_with_vowel?(word) do
    String.match?(word, ~r/^[aeiouâàáãäåæéèêëíìîïóòôõöøúùûüыэюяAEIOUÂÀÁÃÄÅÆÉÈÊËÍÌÎÏÓÒÔÕÖØÚÙÛÜıİ]/u)
  end

  # ---- possessive construction (generic) --------------------------------------

  @spec possessive(String.t(), String.t(), String.t()) :: String.t()
  def possessive(thing, owner, locale) do
    grammar = get(locale)

    case get_in(grammar, ["possessive"]) do
      %{"type" => "genitive"} ->
        apply_genitive(owner, locale) <> " " <> thing

      %{"type" => "pattern"} = rule ->
        pattern =
          if rule["elide_before_vowel"] && starts_with_vowel?(owner) do
            rule["elide_before_vowel"]
          else
            rule["pattern"]
          end

        pattern
        |> String.replace("{owner}", owner)
        |> String.replace("{thing}", thing)

      _ ->
        "#{owner}'s #{thing}"
    end
  end

  # ---- generic morphology engine ----------------------------------------------

  @doc """
  Apply the genitive case to a noun using the language's declared morphology.
  For languages with vowel harmony (Turkish), reads the harmony tables from
  grammar.json. For others, falls back to "'s".
  """
  @spec apply_genitive(String.t(), String.t()) :: String.t()
  def apply_genitive(owner, locale) do
    morph = morphology(locale)
    gen = morph["genitive"]

    cond do
      gen != nil and morph["vowel_harmony"] != nil ->
        vh = morph["vowel_harmony"]
        h4 = harmony4(owner, vh)
        buffer = if ends_in_vowel?(owner, vh), do: gen["vowel_buffer"] || "", else: ""
        owner <> "'" <> buffer <> h4 <> "n"

      true ->
        owner <> "'s"
    end
  end

  @doc """
  Apply the accusative case using the grammar's morphology rules.
  """
  @spec apply_accusative(String.t(), String.t()) :: String.t()
  def apply_accusative(noun, locale) do
    morph = morphology(locale)
    acc = morph["accusative"]

    cond do
      acc != nil and morph["vowel_harmony"] != nil ->
        vh = morph["vowel_harmony"]
        h4 = harmony4(noun, vh)
        buffer = if ends_in_vowel?(noun, vh), do: acc["vowel_buffer"] || "", else: ""
        noun <> "'" <> buffer <> h4

      true ->
        noun
    end
  end

  @doc """
  Apply the dative case using the grammar's morphology rules.
  """
  @spec apply_dative(String.t(), String.t()) :: String.t()
  def apply_dative(noun, locale) do
    morph = morphology(locale)
    dat = morph["dative"]

    cond do
      dat != nil and morph["vowel_harmony"] != nil ->
        vh = morph["vowel_harmony"]
        h2 = harmony2(noun, vh)
        buffer = if ends_in_vowel?(noun, vh), do: dat["vowel_buffer"] || "", else: ""
        noun <> "'" <> buffer <> h2

      true ->
        noun
    end
  end

  @doc """
  Conjugate a verb stem in the progressive aspect using the grammar's rules.
  Works for any language that declares `morphology.progressive`.
  """
  @spec conjugate_progressive(String.t(), String.t(), String.t()) :: String.t()
  def conjugate_progressive(stem, person_key, locale) do
    morph = morphology(locale)
    prog = morph["progressive"]

    cond do
      prog != nil and morph["vowel_harmony"] != nil ->
        vh = morph["vowel_harmony"]
        person_suffix = get_in(prog, ["persons", person_key]) || ""

        case String.split(stem, " ") do
          [single] -> prog_word(single, person_suffix, vh)
          words ->
            {init, [last]} = Enum.split(words, length(words) - 1)
            Enum.join(init, " ") <> " " <> prog_word(last, person_suffix, vh)
        end

      true ->
        stem
    end
  end

  defp prog_word(word, person, vh) do
    trimmed =
      if ends_in_vowel?(word, vh),
        do: String.slice(word, 0..-2//1),
        else: word

    trimmed <> harmony4(trimmed, vh) <> "yor" <> person
  end

  @doc """
  Conjugate a verb stem using the prefix conjugation system.
  Reads the prefix from the pronoun entry's declared key.
  """
  @spec conjugate_prefix(String.t(), String.t() | nil, String.t()) :: String.t()
  def conjugate_prefix(stem, agent_ref, locale) do
    morph = morphology(locale)
    prefix_key = morph["prefix_key"] || "prefix"
    default_prefix = morph["default_prefix"] || ""

    prefix =
      case agent_ref do
        nil -> default_prefix
        ref -> pronoun(ref, locale, prefix_key) || default_prefix
      end

    prefix <> stem
  end

  @doc """
  Apply elision rules declared in the grammar.
  e.g. French: subject \"je\" before vowel-initial verb -> \"j'aime\"
  """
  @spec apply_elision(String.t(), String.t(), String.t()) :: String.t()
  def apply_elision(subject, verb_form, locale) do
    rules = elision_rules(locale)

    Enum.find_value(rules, subject <> " " <> verb_form, fn rule ->
      if rule["subject"] == subject and Regex.match?(~r/#{rule["before"]}/iu, verb_form) do
        rule["result"]
        |> String.replace("{verb}", verb_form)
        |> String.replace("{subject}", subject)
      end
    end)
  end

  # ---- vowel harmony (generic, table-driven) ----------------------------------

  @spec harmony4(String.t(), map()) :: String.t()
  def harmony4(word, vh) do
    table = vh["harmony4"] || %{}
    default = vh["default"] || "i"

    case last_vowel(word, vh) do
      nil -> default
      vowel -> table[vowel] || default
    end
  end

  @spec harmony2(String.t(), map()) :: String.t()
  def harmony2(word, vh) do
    back_vowels = vh["back"] || []
    h2 = vh["harmony2"] || %{}

    case last_vowel(word, vh) do
      nil -> h2["front"] || "e"
      vowel ->
        if vowel in back_vowels, do: h2["back"] || "a", else: h2["front"] || "e"
    end
  end

  @spec last_vowel(String.t(), map()) :: String.t() | nil
  def last_vowel(word, vh) do
    vowels = vh["vowels"] || ~w(a e i o u)

    word
    |> String.downcase()
    |> String.graphemes()
    |> Enum.reverse()
    |> Enum.find(&(&1 in vowels))
  end

  @spec ends_in_vowel?(String.t(), map()) :: boolean()
  def ends_in_vowel?(word, vh) do
    vowels = vh["vowels"] || ~w(a e i o u)

    case word |> String.downcase() |> String.last() do
      nil -> false
      last -> last in vowels
    end
  end

  # ---- lexicon lookups -----------------------------------------------------------

  @spec field_noun(String.t(), String.t(), String.t()) :: String.t()
  def field_noun(field, locale, form \\ "base") do
    key = field |> String.trim() |> String.downcase()

    # field_nouns can be nested under "nouns" or at the top level for compat
    nouns_section = get_in(get(locale), ["nouns", "field_nouns"]) || %{}
    top_section = get_in(get(locale), ["field_nouns"]) || %{}
    merged = Map.merge(top_section, nouns_section)

    case merged[key] do
      %{} = forms -> forms[form] || forms["base"] || field
      noun when is_binary(noun) -> noun
      _ -> String.trim(field)
    end
  end

  @spec pronoun(String.t(), String.t(), String.t()) :: String.t() | nil
  def pronoun(ref, locale, form \\ "subject") do
    get_in(get(locale), ["pronouns", ref, form])
  end

  @spec pronoun_person(String.t(), String.t()) :: String.t() | nil
  def pronoun_person(ref, locale) do
    get_in(get(locale), ["pronouns", ref, "person"])
  end

  @spec verb(String.t(), String.t()) :: map() | nil
  def verb(symbol, locale) do
    get_in(get(locale), ["verbs", symbol])
  end

  @spec preposition(String.t(), String.t()) :: String.t() | nil
  def preposition(role, locale) do
    get_in(get(locale), ["prepositions", role])
  end

  @spec intent(String.t(), String.t()) :: map() | nil
  def intent(name, locale) do
    get_in(get(locale), ["intents", name])
  end

  @spec default_subject(String.t()) :: String.t() | nil
  def default_subject(locale), do: get_in(sentence_rules(locale), ["default_subject"])

  @spec unsupported_response(String.t()) :: String.t() | nil
  def unsupported_response(locale) do
    get_in(get(locale), ["unsupported_language_response"])
  end

  # ---- parts of speech accessors -----------------------------------------------

  @spec nouns(String.t()) :: map()
  def nouns(locale), do: get_in(get(locale), ["nouns"]) || %{}

  @spec adjectives(String.t()) :: map()
  def adjectives(locale), do: get_in(get(locale), ["adjectives"]) || %{}

  @spec adjective_position(String.t()) :: String.t()
  def adjective_position(locale) do
    get_in(get(locale), ["adjectives", "position"]) ||
      get_in(get(locale), ["sentence_rules", "adjective_position"]) ||
      "before"
  end

  @spec adjective(String.t(), String.t()) :: map() | nil
  def adjective(word, locale) do
    get_in(get(locale), ["adjectives", "common", word])
  end

  @spec adverbs(String.t()) :: map()
  def adverbs(locale), do: get_in(get(locale), ["adverbs"]) || %{}

  @spec adverb(String.t(), String.t()) :: map() | nil
  def adverb(word, locale) do
    get_in(get(locale), ["adverbs", "common", word])
  end

  @spec conjunctions(String.t()) :: map()
  def conjunctions(locale), do: get_in(get(locale), ["conjunctions"]) || %{}

  @spec conjunction(String.t(), String.t(), String.t()) :: String.t() | nil
  def conjunction(word, kind, locale) do
    get_in(get(locale), ["conjunctions", kind, word])
  end

  @spec interjections(String.t()) :: map()
  def interjections(locale), do: get_in(get(locale), ["interjections"]) || %{}

  @spec interjection_for(String.t(), String.t()) :: String.t() | nil
  def interjection_for(category, locale) do
    case get_in(get(locale), ["interjections", category]) do
      list when is_list(list) and list != [] -> Enum.random(list)
      _ -> nil
    end
  end

  @spec article(String.t(), String.t()) :: String.t() | nil
  def article(kind, locale) do
    get_in(get(locale), ["nouns", "articles", kind])
  end
end
