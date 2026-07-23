defmodule LangOS.Realizer do
  @moduledoc """
  Language-agnostic natural language generation.

  Composes sentences from Semantic IR graphs or communicative intents using
  the grammatical rules declared in each language pack's `grammar.json`.
  No language-specific code exists here — only a generic interpreter of the
  pack's declarative rules: word order, morphology type, conjugation system,
  elision, and possessive construction.

  Adding a new language (including non-Latin scripts like Arabic, Cyrillic, or
  CJK) requires only adding a `packs/<id>/grammar.json` — zero Elixir changes.
  """

  alias LangOS.Grammar

  # ===========================================================================
  # Intent realization (missing_fields, success, error, …)
  # ===========================================================================

  @spec intent(String.t(), String.t(), String.t(), map()) ::
          {:ok, String.t()} | :unsupported
  def intent(name, locale, tone, data) do
    with %{"recipes" => recipes} = spec <- Grammar.intent(name, locale),
         usable when usable != [] <- usable_recipes(recipes, tone, data) do
      recipe = Enum.random(usable)
      body = fill_slots(recipe["text"], locale, data)
      opener = maybe_opener(spec, tone)

      {:ok, assemble(opener, body)}
    else
      _ -> :unsupported
    end
  end

  defp usable_recipes(recipes, tone, data) do
    by_tone =
      Enum.filter(recipes, fn r ->
        tones = r["tones"] || []
        tones == [] or tone in tones
      end)

    candidates = if by_tone == [], do: recipes, else: by_tone
    Enum.filter(candidates, fn r -> slots_satisfied?(r["text"], data) end)
  end

  defp slots_satisfied?(text, data) do
    ~r/\{(\w+)\}/
    |> Regex.scan(text, capture: :all_but_first)
    |> List.flatten()
    |> Enum.all?(fn
      "fields" -> present?(data["fields"])
      "fields_of" -> present?(data["fields"]) and present?(data["entity"])
      "be" -> present?(data["fields"])
      slot -> present?(data[slot])
    end)
  end

  defp present?(nil), do: false
  defp present?(""), do: false
  defp present?([]), do: false
  defp present?(_), do: true

  defp maybe_opener(spec, tone) do
    openers = get_in(spec, ["openers", tone]) || []
    if openers != [] and :rand.uniform(2) == 1, do: Enum.random(openers)
  end

  defp assemble(nil, body), do: sentence_case(body)
  defp assemble(opener, body), do: sentence_case(opener <> " " <> body)

  defp sentence_case(text) do
    text = String.trim(text)

    text =
      case String.first(text) do
        nil -> text
        first -> String.upcase(first) <> String.slice(text, 1..-1//1)
      end

    if String.match?(text, ~r/[.!?。！？]$/u), do: text, else: text <> "."
  end

  # ---- slot filling ------------------------------------------------------------

  defp fill_slots(text, locale, data) do
    fields = field_items(data["fields"])

    replacements = %{
      "fields" => fn -> fields_np(fields, locale) end,
      "fields_of" => fn ->
        Grammar.possessive(fields_np(fields, locale), to_string(data["entity"]), locale)
      end,
      "be" => fn -> if length(fields) == 1, do: "is", else: "are" end,
      "entity" => fn -> to_string(data["entity"]) end,
      "action" => fn -> to_string(data["action"]) end,
      "reason" => fn -> to_string(data["reason"]) end,
      "name" => fn -> to_string(data["name"]) end,
      "summary" => fn -> to_string(data["summary"]) end
    }

    Regex.replace(~r/\{(\w+)\}/, text, fn whole, slot ->
      case replacements[slot] do
        nil -> whole
        build -> build.()
      end
    end)
  end

  defp field_items(nil), do: []
  defp field_items(fields) when is_list(fields), do: Enum.map(fields, &to_string/1)

  defp field_items(fields) when is_binary(fields) do
    fields
    |> String.split(~r/\s*,\s*/)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp fields_np(fields, locale) do
    morph = Grammar.morphology(locale)
    has_poss = morph["vowel_harmony"] != nil or morph["type"] == "agglutinative"
    form = if has_poss, do: "poss", else: "base"

    fields
    |> Enum.map(&Grammar.field_noun(&1, locale, form))
    |> Enum.uniq()
    |> Grammar.list_join(locale)
  end

  # ===========================================================================
  # IR realization — fully generic
  # ===========================================================================

  @spec from_ir(map(), String.t()) :: String.t()
  def from_ir(%{"graph" => %{"nodes" => nodes, "edges" => edges}} = ir, locale) do
    pred = Enum.find(nodes, fn n -> n["type"] == "predicate" end)
    symbol = get_in(pred || %{}, ["predicate", "symbol"]) || "UNKNOWN"
    node_index = Map.new(nodes, fn n -> {n["id"], n} end)

    roles =
      Enum.reduce(edges, %{}, fn %{"role" => role, "to" => to}, acc ->
        Map.put_new(acc, role, Map.get(node_index, to))
      end)

    utterance = ir["utterance_type"] || "statement"
    generic_sentence(symbol, roles, utterance, locale)
  end

  def from_ir(%{"source" => %{"text" => text}}, _locale) when is_binary(text), do: text
  def from_ir(_, _), do: "Done."

  # ---- generic sentence builder -----------------------------------------------

  defp generic_sentence(symbol, roles, utterance, locale) do
    verb_entry = Grammar.verb(symbol, locale) || %{}

    # META_ predicates (greetings, thanks, farewells) → use the language's
    # interjections for a natural, human response instead of a clause.
    if verb_entry["fixed"] != nil and String.starts_with?(symbol, "META_") do
      realize_meta(symbol, verb_entry, locale)
    else
      realize_clause(symbol, verb_entry, roles, utterance, locale)
    end
  end

  defp realize_meta(symbol, verb_entry, locale) do
    category =
      case symbol do
        "META_GREET" -> "greeting"
        "META_THANK" -> "thanks"
        "META_FAREWELL" -> "farewell"
        "META_APOLOGIZE" -> "apology"
        _ -> nil
      end

    interjection = if category, do: Grammar.interjection_for(category, locale)

    text = interjection || verb_entry["fixed"] || humanize(symbol)

    case String.first(text) do
      nil -> text
      first -> String.upcase(first) <> String.slice(text, 1..-1//1)
    end
    |> then(fn t ->
      if String.match?(t, ~r/[.!?。！？]$/u), do: t, else: t <> "."
    end)
  end

  defp realize_clause(symbol, verb_entry, roles, utterance, locale) do
    order = Grammar.word_order(locale)
    conj_type = Grammar.conjugation_type(locale)

    subject_node = roles["agent"]
    object_node = roles["patient"] || roles["theme"]

    subject = filler(subject_node, locale, "subject")
    object = realize_object(object_node, locale)
    agent_ref = ref_of(subject_node)

    verb_form = conjugate_verb(verb_entry, utterance, agent_ref, conj_type, locale)

    subject_verb =
      if subject != nil and verb_form != nil do
        Grammar.apply_elision(subject, verb_form, locale)
      else
        nil
      end

    trailers = realize_trailers(roles, locale)

    parts =
      case {order, utterance} do
        {_, "command"} ->
          imp = verb_entry["imp"] || verb_entry["stem"] || humanize(symbol)
          assemble_order(order, nil, imp, object, trailers, true)

        {"SOV", _} ->
          assemble_order("SOV", subject_verb || subject, verb_form, object, trailers, false)

        _ ->
          assemble_order("SVO", subject_verb || subject, verb_form, object, trailers, false)
      end

    finish(parts, utterance, locale)
  end

  defp assemble_order("SOV", subject, verb, object, trailers, is_command) do
    if is_command do
      [object] ++ trailers ++ [verb]
    else
      [subject, object] ++ trailers ++ [verb]
    end
  end

  defp assemble_order(_svo, subject, verb, object, trailers, is_command) do
    if is_command do
      [verb, object] ++ trailers
    else
      default_subj = subject || "someone"
      [default_subj, verb, object] ++ trailers
    end
  end

  # ---- verb conjugation (generic, driven by grammar.json) ---------------------

  defp conjugate_verb(verb_entry, utterance, agent_ref, conj_type, locale) do
    cond do
      verb_entry["fixed"] ->
        verb_entry["fixed"]

      utterance == "command" ->
        verb_entry["imp"] || verb_entry["stem"] || nil

      conj_type == "prefix" and verb_entry["stem"] ->
        Grammar.conjugate_prefix(verb_entry["stem"], agent_ref, locale)

      conj_type == "suffix" and verb_entry["stem"] ->
        person = Grammar.pronoun_person(agent_ref || "REF_PREVIOUS_ENTITY", locale) || "3s"
        Grammar.conjugate_progressive(verb_entry["stem"], person, locale)

      conj_type == "lexical" ->
        person = Grammar.pronoun_person(agent_ref || "REF_PREVIOUS_ENTITY", locale)
        stmt_key = if person == "1s", do: "stmt_1s", else: "stmt"
        verb_entry[stmt_key] || verb_entry["stmt"] || nil

      true ->
        verb_entry["stmt"] || verb_entry["stem"] || nil
    end
  end

  # ---- object realization (case marking for SOV languages) --------------------

  defp realize_object(nil, _locale), do: nil

  defp realize_object(node, locale) do
    morph = Grammar.morphology(locale)
    label = filler(node, locale, "object")

    cond do
      node["type"] == "reference" -> label
      morph["accusative"] != nil and node_kind(node) == "named" ->
        Grammar.apply_accusative(label, locale)
      true -> label
    end
  end

  # ---- trailer realization (prepositional / case-marked phrases) ---------------

  @trailing_roles ["container", "goal", "source", "beneficiary", "instrument"]

  defp realize_trailers(roles, locale) do
    morph = Grammar.morphology(locale)
    has_case = morph["dative"] != nil

    for role <- @trailing_roles,
        node = roles[role],
        label = filler(node, locale, "object"),
        label != nil do
      prep = Grammar.preposition(role, locale)

      cond do
        has_case and node_kind(node) == "named" ->
          Grammar.apply_dative(label, locale)

        prep != nil ->
          prep <> " " <> label

        true ->
          label
      end
    end
  end

  # ---- shared helpers ---------------------------------------------------------

  defp filler(nil, _locale, _case_form), do: nil

  defp filler(%{"type" => "reference", "reference" => %{"ref" => ref}}, locale, case_form) do
    Grammar.pronoun(ref, locale, case_form) || Grammar.pronoun(ref, "en", case_form) || "it"
  end

  defp filler(%{"type" => "concept", "concept" => %{"canonical" => c}}, _locale, _), do: c
  defp filler(_, _, _), do: nil

  defp node_kind(%{"type" => "concept", "concept" => %{"kind" => kind}}), do: kind
  defp node_kind(%{"type" => "reference"}), do: "reference"
  defp node_kind(_), do: nil

  defp ref_of(%{"type" => "reference", "reference" => %{"ref" => ref}}), do: ref
  defp ref_of(_), do: nil

  defp finish(parts, utterance, locale) do
    sentence =
      parts
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.join(" ")
      |> String.trim()

    # Capitalize first character if the grammar says so (most do; some scripts
    # like Arabic or CJK don't have uppercase so this is a no-op).
    capitalize = get_in(Grammar.sentence_rules(locale), ["capitalize_first"]) != false

    sentence =
      if capitalize do
        case String.first(sentence) do
          nil -> sentence
          first -> String.upcase(first) <> String.slice(sentence, 1..-1//1)
        end
      else
        sentence
      end

    # Use the default subject if the sentence would otherwise start with
    # just a verb and the grammar declares one.
    if sentence == "" do
      "Done."
    else
      punct = if utterance == "question", do: "?", else: "."
      if String.match?(sentence, ~r/[.!?。！？]$/u), do: sentence, else: sentence <> punct
    end
  end

  defp humanize(symbol) do
    symbol
    |> String.replace(~r/^(ACTION|STATE|EVENT|QUERY|META)_/, "")
    |> String.downcase()
    |> String.replace("_", " ")
  end
end
