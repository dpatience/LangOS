defmodule LangOS.Engine.Lexical do
  @moduledoc """
  Lexical decomposition engine — understands complex sentences by scanning
  every token against the grammar.json parts-of-speech lexicon.

  Unlike the Rule engine (regex patterns) or Syntax engine (clause structure),
  this engine works bottom-up: it identifies known words (verbs, field nouns,
  pronouns, prepositions, conjunctions, interjections) from the grammar pack,
  then assembles meaning from the recognized parts.

  This lets LangOS understand:
    * Its own express output (roundtrip understanding)
    * Complex multi-clause sentences
    * Sentences with lists of nouns ("age, email, and phone")
    * Possessive constructions ("Patience'nin yaşı")
    * Intent-like sentences ("please provide X's Y")

  Placed in the parse chain after Rule and Syntax — catches what they miss.
  """
  use LangOS.Engine

  alias LangOS.{Grammar, LanguagePack, SemanticGraph, Vocabulary}

  @engine_info %{"parser" => "lexical_decomposition", "version" => "1.0.0"}

  @word_regex ~r/[\p{L}\p{N}''-]+/u

  @impl true
  def capabilities, do: [:parse, :extract]

  @impl true
  def health, do: :ok

  @impl true
  def parse(text, opts) do
    locale = Keyword.get(opts, :locale) || "en"
    trimmed = String.trim(text)

    if trimmed == "" do
      {:error, :empty_text}
    else
      case decompose(trimmed, locale) do
        {:ok, tree} -> {:ok, tree}
        :no_parse -> {:error, :no_parse}
      end
    end
  end

  @impl true
  def extract_meaning(parse_tree, opts) do
    locale = Keyword.get(opts, :locale, "en")
    text = Keyword.get(opts, :text, "")
    engine = Map.merge(@engine_info, %{"language_pack" => locale})

    graph = SemanticGraph.new()

    {graph, pred_id} =
      SemanticGraph.add_predicate_node(graph, parse_tree["vocab_id"], parse_tree["symbol"])

    graph =
      Enum.reduce(parse_tree["arguments"] || [], graph, fn arg, g ->
        surface = arg["label"] || ""
        span = arg["span"] || [0, byte_size(text)]

        {g2, node_id} =
          if arg["ref"] do
            SemanticGraph.add_reference_node(g, arg["ref"])
          else
            canonical = arg["canonical"] || String.downcase(surface)
            SemanticGraph.add_concept_node(g, canonical, arg["kind"] || "literal")
          end

        g2
        |> SemanticGraph.add_edge(pred_id, node_id, arg["role"])
        |> SemanticGraph.add_mention(node_id, surface, span)
      end)

    confidence = %{
      "overall" => parse_tree["confidence"] || 0.65,
      "predicate" => parse_tree["confidence"] || 0.65,
      "roles" => 0.7,
      "references" => 1.0
    }

    unit_type = parse_tree["unit_type"] || "statement"
    {:ok, SemanticGraph.to_ir(graph, locale, text, unit_type, confidence, engine)}
  end

  # ---------------------------------------------------------------------------
  # Core decomposition: scan tokens against grammar.json parts of speech
  # ---------------------------------------------------------------------------

  defp decompose(text, locale) do
    grammar = Grammar.get(locale)
    if grammar == %{}, do: throw(:no_grammar)

    tokens = word_tokens(text)

    # Build reverse lookup indexes from grammar.json
    verb_index = build_verb_index(grammar)
    field_noun_index = build_field_noun_index(grammar)
    pronoun_index = build_pronoun_index(grammar)
    interjection_index = build_interjection_index(grammar)
    conjunction_index = build_conjunction_index(grammar)
    preposition_index = build_preposition_index(grammar)

    # Also check the language pack's verb_map for surface forms
    pack_verb_map = LanguagePack.Registry.verb_map(locale)

    # Phase 1: Identify all recognized tokens
    recognized =
      tokens
      |> Enum.with_index()
      |> Enum.map(fn {{lower, surface, start, stop}, idx} ->
        # Strip possessive markers for matching
        stripped = strip_possessive(lower)

        cond do
          # Check interjections first (greetings, thanks, etc.)
          entry = Map.get(interjection_index, lower) ->
            {idx, {:interjection, entry, surface, start, stop}}

          # Check pack verb_map (surface verb forms, with stem stripping)
          entry = Map.get(pack_verb_map, lower) || find_in_verb_map(lower, pack_verb_map) ->
            {idx, {:verb, entry, surface, start, stop}}

          # Check grammar.json verb stems/forms
          entry = match_verb(lower, verb_index) ->
            {idx, {:verb, entry, surface, start, stop}}

          # Check field nouns (age, yaşı, imyaka, etc.)
          field = match_field_noun(lower, stripped, field_noun_index) ->
            {idx, {:field_noun, field, surface, start, stop}}

          # Check pronouns
          ref = Map.get(pronoun_index, lower) ->
            {idx, {:pronoun, ref, surface, start, stop}}

          # Check conjunctions
          Map.has_key?(conjunction_index, lower) ->
            {idx, {:conjunction, lower, surface, start, stop}}

          # Check prepositions
          role = Map.get(preposition_index, lower) ->
            {idx, {:preposition, role, surface, start, stop}}

          true ->
            {idx, {:unknown, lower, surface, start, stop}}
        end
      end)

    # Phase 2: Determine the sentence's primary meaning
    verbs = for {_, {:verb, entry, s, st, sp}} <- recognized, do: {entry, s, st, sp}
    fields = for {_, {:field_noun, field, s, st, sp}} <- recognized, do: {field, s, st, sp}
    pronouns = for {_, {:pronoun, ref, s, st, sp}} <- recognized, do: {ref, s, st, sp}
    interjections = for {_, {:interjection, entry, s, st, sp}} <- recognized, do: {entry, s, st, sp}
    unknowns = for {_, {:unknown, lower, s, st, sp}} <- recognized, lower not in noise_words(), do: {lower, s, st, sp}

    # Find named entities (capitalized unknowns that aren't sentence-initial)
    named_entities =
      recognized
      |> Enum.filter(fn
        {idx, {:unknown, _lower, surface, _st, _sp}} ->
          idx > 0 and capitalized?(surface) and String.length(surface) > 1
        _ -> false
      end)
      |> Enum.map(fn {_, {:unknown, _, surface, start, stop}} -> {surface, start, stop} end)

    # Also check for possessive-marked names (Patience'nin -> Patience)
    possessive_names =
      tokens
      |> Enum.filter(fn {lower, surface, _, _} ->
        String.contains?(lower, "'") and capitalized?(surface)
      end)
      |> Enum.map(fn {_lower, surface, start, stop} ->
        name = surface |> String.split(~r/['']/) |> hd()
        {name, start, stop}
      end)

    all_entities = (named_entities ++ possessive_names) |> Enum.uniq_by(&elem(&1, 0))

    # Phase 3: Decide the semantic interpretation
    #
    # The lexical engine is intentionally selective — it only handles cases
    # that the syntax engine CANNOT: field noun patterns (missing_fields
    # requests) and interjection recognition. For standard verb+object
    # sentences, the syntax engine with its clause structure parsing is better.
    cond do
      # Interjection-only sentence (greeting, thanks, farewell)
      # — only when no verbs detected (otherwise it's a real sentence)
      interjections != [] and verbs == [] and fields == [] ->
        {entry, surface, start, stop} = hd(interjections)
        args = [%{"role" => "theme", "kind" => "literal", "label" => surface, "span" => [start, stop]}]
        {:ok, tree(entry, "statement", args, 0.8)}

      # Sentence with 2+ field nouns → almost certainly a request for information
      # This is the lexical engine's primary strength: decomposing complex
      # "please provide X's age, email, and phone" type sentences.
      fields != [] and length(fields) >= 2 ->
        build_field_sentence(text, verbs, fields, all_entities, pronouns, unknowns, locale)

      # Single field noun with a named entity → still likely a field request
      fields != [] and all_entities != [] ->
        build_field_sentence(text, verbs, fields, all_entities, pronouns, unknowns, locale)

      # Everything else: let the syntax engine handle it (it has better
      # clause structure parsing for subject/verb/object sentences)
      true ->
        :no_parse
    end
  catch
    :no_grammar -> :no_parse
  end

  # When we find field nouns, this is likely a request for information
  # or a description of what fields are needed. The verb is secondary —
  # the presence of field nouns IS the signal.
  defp build_field_sentence(text, verbs, fields, entities, pronouns, _unknowns, _locale) do
    # Prefer specific "provide/enter/give" verbs over incidental verbs like "continue/resume"
    provide_verbs = ["ACTION_SEND", "ACTION_GIVE", "ACTION_SHOW", "ACTION_ASSIGN",
                     "ACTION_CREATE", "ACTION_UPDATE", "ACTION_WRITE", "ACTION_REGISTER",
                     "ACTION_SHARE", "ACTION_EXPLAIN", "ACTION_TELL"]
    noise_verbs = ["ACTION_RESUME", "ACTION_PAUSE", "ACTION_WAIT", "ACTION_START",
                   "ACTION_STOP", "ACTION_MOVE", "ACTION_TRAVEL", "ACTION_CLOSE",
                   "ACTION_OPEN", "ACTION_READ", "ACTION_SEARCH", "STATE_BE",
                   "STATE_HAVE", "STATE_NEED", "STATE_WANT", "STATE_KNOW"]

    {entry, _verb_type} =
      case find_verb_by_priority(verbs, provide_verbs) do
        nil ->
          # Filter out noise verbs (continue, wait, etc.) that aren't the real action
          real_verbs = Enum.reject(verbs, fn {e, _, _, _} -> e["symbol"] in noise_verbs end)
          case real_verbs do
            [{entry, _, _, _} | _] -> {entry, :found}
            [] ->
              # Default to a request/provide action when only field nouns are present
              request_entry = Vocabulary.by_symbol("ACTION_SHOW") ||
                              %{"id" => "ACT_000010", "symbol" => "ACTION_SHOW", "category" => "ACT"}
              {request_entry, :inferred}
          end
        {entry, _, _, _} ->
          {entry, :found}
      end

    args = []

    # Entity becomes the possessor/beneficiary — strip possessive suffixes
    args =
      case entities do
        [{name, start, stop} | _] ->
          clean_name = name |> String.split(~r/['']/) |> hd()
          args ++ [%{"role" => "beneficiary", "kind" => "named", "label" => clean_name,
                     "canonical" => String.downcase(clean_name), "span" => [start, stop]}]
        [] ->
          case pronouns do
            [{ref, surface, start, stop} | _] ->
              args ++ [%{"role" => "beneficiary", "kind" => "pronoun", "label" => surface,
                         "ref" => ref, "span" => [start, stop]}]
            [] -> args
          end
      end

    # Field nouns become the theme (what's being requested)
    field_labels = Enum.map(fields, fn {field, surface, start, stop} ->
      %{"role" => "theme", "kind" => "literal", "label" => surface,
        "canonical" => field, "span" => [start, stop]}
    end)

    args = args ++ field_labels

    unit =
      cond do
        String.ends_with?(String.trim(text), "?") -> "question"
        String.ends_with?(String.trim(text), "!") -> "command"
        true -> "command"
      end

    {:ok, tree(entry, unit, args, 0.65)}
  end

  defp find_verb_by_priority(verbs, priority_symbols) do
    Enum.find(verbs, fn {entry, _, _, _} ->
      entry["symbol"] in priority_symbols
    end) || List.first(verbs)
  end

  # ---------------------------------------------------------------------------
  # Reverse lexicon builders — turn grammar.json into lookup maps
  # ---------------------------------------------------------------------------

  defp build_verb_index(grammar) do
    verbs = grammar["verbs"] || %{}

    Enum.reduce(verbs, %{}, fn
      {"_doc", _}, acc -> acc
      {symbol, forms}, acc when is_map(forms) ->
        entry = Vocabulary.by_symbol(symbol) ||
                %{"id" => symbol, "symbol" => symbol, "category" => infer_category(symbol)}

        Enum.reduce(forms, acc, fn
          {"_doc", _}, inner -> inner
          {form_key, form_val}, inner when is_binary(form_val) and form_key in ~w(imp stmt stmt_1s gerund infinitive stem fixed) ->
            # Index each word of multi-word forms too (e.g. "search for" -> "search")
            words = String.split(form_val, " ")
            Enum.reduce(words, Map.put(inner, String.downcase(form_val), {entry, form_key}), fn w, i ->
              Map.put_new(i, String.downcase(w), {entry, form_key})
            end)
          _, inner -> inner
        end)
      _, acc -> acc
    end)
  end

  defp build_field_noun_index(grammar) do
    nouns_section = get_in(grammar, ["nouns", "field_nouns"]) || %{}
    top_section = grammar["field_nouns"] || %{}
    merged = Map.merge(top_section, nouns_section)

    Enum.reduce(merged, %{}, fn
      {"_doc", _}, acc -> acc
      {field, forms}, acc when is_map(forms) ->
        # Index all surface forms: base, poss, display, etc.
        Enum.reduce(forms, acc, fn
          {_key, val}, inner when is_binary(val) ->
            index_field_form(inner, field, val)
          _, inner -> inner
        end)
      {field, noun}, acc when is_binary(noun) ->
        index_field_form(acc, field, noun)
      _, acc -> acc
    end)
  end

  defp index_field_form(acc, field, val) do
    stripped = val |> strip_article() |> String.downcase()
    # Index the full form, stripped form, and individual words
    acc = Map.put(Map.put(acc, String.downcase(val), field), stripped, field)
    # Also index individual content words (for multi-word nouns like "date de naissance")
    words = stripped |> String.split(~r/[\s-]+/) |> Enum.reject(&(&1 in ~w(de du des le la les l un une the a an der die das ein eine)))
    Enum.reduce(words, acc, fn w, inner ->
      if String.length(w) > 2, do: Map.put_new(inner, w, field), else: inner
    end)
  end

  defp build_pronoun_index(grammar) do
    pronouns = grammar["pronouns"] || %{}

    Enum.reduce(pronouns, %{}, fn
      {"_doc", _}, acc -> acc
      {ref, forms}, acc when is_map(forms) ->
        Enum.reduce(forms, acc, fn
          {_key, val}, inner when is_binary(val) and val != "" ->
            Map.put(inner, String.downcase(val), ref)
          _, inner -> inner
        end)
      _, acc -> acc
    end)
  end

  defp build_interjection_index(grammar) do
    interjections = grammar["interjections"] || %{}

    Enum.reduce(interjections, %{}, fn
      {"_doc", _}, acc -> acc
      {category, words}, acc when is_list(words) ->
        meta_symbol = category_to_meta(category)
        entry = Vocabulary.by_symbol(meta_symbol) ||
                %{"id" => meta_symbol, "symbol" => meta_symbol, "category" => "META"}

        Enum.reduce(words, acc, fn word, inner when is_binary(word) ->
          Map.put(inner, String.downcase(word), entry)
        end)
      _, acc -> acc
    end)
  end

  defp build_conjunction_index(grammar) do
    conjs = grammar["conjunctions"] || %{}

    Enum.reduce(conjs, %{}, fn
      {"_doc", _}, acc -> acc
      {_type, words}, acc when is_map(words) ->
        Enum.reduce(words, acc, fn {key, val}, inner ->
          inner
          |> Map.put(String.downcase(key), "conjunction")
          |> Map.put(String.downcase(val), "conjunction")
        end)
      _, acc -> acc
    end)
  end

  defp build_preposition_index(grammar) do
    preps = grammar["prepositions"] || %{}

    Enum.reduce(preps, %{}, fn
      {"_doc", _}, acc -> acc
      {role, val}, acc when is_binary(val) ->
        val |> String.split("/") |> Enum.reduce(acc, fn w, inner ->
          Map.put(inner, String.downcase(String.trim(w)), role)
        end)
      _, acc -> acc
    end)
  end

  # ---------------------------------------------------------------------------
  # Token-level matching helpers
  # ---------------------------------------------------------------------------

  defp match_verb(lower, verb_index) do
    case Map.get(verb_index, lower) do
      {entry, _form} -> entry
      nil ->
        # Try progressive stem stripping for agglutinative verbs:
        # "paylaşırsanız" -> "paylaşır" -> "paylaş"
        # "girin" -> "gir"
        find_verb_by_stem(lower, verb_index)
    end
  end

  defp find_in_verb_map(word, verb_map) do
    len = String.length(word)
    if len < 3 do
      nil
    else
      3..max(3, len - 1)
      |> Enum.reverse()
      |> Enum.find_value(fn take ->
        stem = String.slice(word, 0, take)
        Map.get(verb_map, stem)
      end)
    end
  end

  defp find_verb_by_stem(word, verb_index) do
    len = String.length(word)
    if len < 3, do: nil, else: do_stem_search(word, len, verb_index)
  end

  defp do_stem_search(word, len, verb_index) do
    # Try progressively shorter prefixes of the word as stems
    3..max(3, len - 1)
    |> Enum.reverse()
    |> Enum.find_value(fn take ->
      stem = String.slice(word, 0, take)
      case Map.get(verb_index, stem) do
        {entry, _form} -> entry
        nil -> nil
      end
    end)
  end

  defp match_field_noun(lower, stripped, field_noun_index) do
    Map.get(field_noun_index, lower) ||
      Map.get(field_noun_index, stripped) ||
      # Try without trailing possessive suffixes (Turkish: yaşı -> yaş)
      match_field_without_suffix(lower, field_noun_index)
  end

  defp match_field_without_suffix(lower, index) do
    # Try progressively shorter suffixes for agglutinative languages
    suffixes = ["ı", "i", "u", "ü", "sı", "si", "su", "sü", "ası", "esi"]
    Enum.find_value(suffixes, fn suf ->
      base = String.replace_suffix(lower, suf, "")
      if base != lower, do: Map.get(index, base)
    end)
  end

  defp strip_possessive(word) do
    word
    |> String.split(~r/['']/)
    |> hd()
  end

  defp strip_article(noun) do
    noun
    |> String.replace(~r/^(the|a|an|le|la|les|l'|un|une|des|der|die|das|ein|eine|el|los|las)\s+/iu, "")
    |> String.replace(~r/^l'/iu, "")
  end

  defp capitalized?(surface) do
    case String.first(surface) do
      nil -> false
      first -> String.match?(first, ~r/^\p{Lu}$/u)
    end
  end

  defp noise_words do
    ~w(the a an de du des le la les l un une der die das ein eine
       lütfen please bitte s'il ne pas not so we can
       için ya da olan ve veya et ou und oder na ni ko
       devam etmeden önce avant before bevor gukomeza
       nous il ils elle on ce qui que dont
       wir uns ihr sie es noch
       move forward continue
       share provide give send still need just can
       turacyakeneye mbere
       paylaşırsanız edelim
       fortfahren brauchen)
  end

  defp category_to_meta("greeting"), do: "META_GREET"
  defp category_to_meta("farewell"), do: "META_FAREWELL"
  defp category_to_meta("thanks"), do: "META_THANK"
  defp category_to_meta("apology"), do: "META_APOLOGIZE"
  defp category_to_meta("surprise"), do: "META_SURPRISE"
  defp category_to_meta("agreement"), do: "META_AGREE"
  defp category_to_meta("disagreement"), do: "META_DISAGREE"
  defp category_to_meta("encouragement"), do: "META_ENCOURAGE"
  defp category_to_meta("frustration"), do: "META_FRUSTRATE"
  defp category_to_meta(_), do: "META_UNKNOWN"

  defp infer_category("ACTION_" <> _), do: "ACT"
  defp infer_category("STATE_" <> _), do: "STA"
  defp infer_category("EVENT_" <> _), do: "EVT"
  defp infer_category("META_" <> _), do: "META"
  defp infer_category("QUERY_" <> _), do: "QRY"
  defp infer_category(_), do: "ACT"

  defp tree(entry, unit, args, confidence) do
    %{
      "vocab_id" => entry["id"],
      "symbol" => entry["symbol"],
      "unit_type" => unit,
      "arguments" => args,
      "confidence" => confidence
    }
  end

  defp word_tokens(text) do
    Regex.scan(@word_regex, text, return: :index)
    |> Enum.map(fn [{start, len}] ->
      surface = binary_part(text, start, len)
      {String.downcase(surface), surface, start, start + len}
    end)
  end
end
