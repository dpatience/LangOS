defmodule LangOS.Engine.Syntax do
  @moduledoc """
  Deterministic structural parser — the heart of the understanding pipeline.

  Stages (per the LangOS architecture):

      Tokenizer -> Morphological Analyzer -> Dependency Parser
                -> Semantic Mapper -> Graph Builder

  The parser first discovers linguistic structure — question markers, the
  main verb, its subject, its objects, and prepositional attachments — and
  only then maps the verb lemma onto the Semantic Vocabulary. Intent is an
  outcome of structure, never a classification step:

      "Can I join the class?"
        aux: can (question)   verb: join -> EVT_000001
        subject: I -> REF_SPEAKER (patient)
        object: class (container)

  Question-ness lives in `utterance_type`, not in the predicate. Grammatical
  question forms ("what is the meaning of X") map to semantic actions
  (ACTION_DEFINE) with the real object as theme.

  Only the Semantic Mapper stage knows vocabulary IDs. Everything before it
  works purely with language, which is what lets the same pipeline serve
  English, French, Kinyarwanda, and future packs.
  """
  use LangOS.Engine

  alias LangOS.{Lexicon, LanguagePack, SemanticGraph, Vocabulary}

  @engine_info %{"parser" => "syntax_structural", "language_pack" => "en", "version" => "1.0.0"}

  @word_regex ~r/[\p{L}\p{N}']+/u

  # Closed-class words never selected as the main verb.
  @aux ~w(am is are was were be been being do does did have has had
          will would can could shall should may might must)
  @modals ~w(can could may might will would shall should must do does did)
  @copulas ~w(am is are was were be been being)
  @wh ~w(what who where when why how which whose whom)
  @determiners ~w(the a an)
  @subject_noise ~w(not never please) ++ @aux

  # Dependency label -> semantic role, per attachment preposition.
  @prep_roles %{
    "in" => "container",
    "into" => "container",
    "inside" => "container",
    "to" => "goal",
    "onto" => "goal",
    "toward" => "goal",
    "towards" => "goal",
    "from" => "source",
    "of" => "theme",
    "about" => "theme",
    "regarding" => "theme",
    "for" => "beneficiary",
    "with" => "instrument",
    "using" => "instrument",
    "at" => "time",
    "on" => "time",
    "by" => "time"
  }

  @wh_focus %{
    "who" => "person",
    "where" => "location",
    "when" => "time",
    "why" => "reason",
    "how" => "manner",
    "which" => "choice",
    "whose" => "possessor"
  }

  @define %{"id" => "ACT_000221", "symbol" => "ACTION_DEFINE", "category" => "ACT"}
  @be %{"id" => "STA_000001", "symbol" => "STATE_BE", "category" => "STA"}
  @have %{"id" => "STA_000002", "symbol" => "STATE_HAVE", "category" => "STA"}

  @impl true
  def capabilities, do: [:parse, :extract]

  @impl true
  def health do
    if Lexicon.entry_count("en") > 0, do: :ok, else: {:error, :lexicon_not_loaded}
  end

  @impl true
  def parse(text, opts) do
    locale = Keyword.get(opts, :locale) || "en"
    trimmed = String.trim(text)

    cond do
      trimmed == "" -> {:error, :empty_text}
      locale == "en" -> parse_en(trimmed)
      true -> parse_pack(trimmed, locale)
    end
  end

  @impl true
  def extract_meaning(parse_tree, opts) do
    locale = Keyword.get(opts, :locale, "en")
    text = Keyword.get(opts, :text, "")
    engine = Map.put(@engine_info, "language_pack", locale)

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
      "overall" => parse_tree["confidence"] || 0.8,
      "predicate" => parse_tree["confidence"] || 0.8,
      "roles" => 0.8,
      "references" => 1.0
    }

    unit_type = parse_tree["unit_type"] || "statement"
    {:ok, SemanticGraph.to_ir(graph, locale, text, unit_type, confidence, engine)}
  end

  # ---- English: constructions, then clause structure ---------------------

  defp parse_en(text) do
    case match_construction(text) do
      {:ok, tree} -> {:ok, tree}
      :no_match -> parse_clause(text)
    end
  end

  # Grammatical constructions whose surface form is interrogative but whose
  # meaning is a plain semantic action. Matched before clause parsing.
  defp match_construction(text) do
    constructions = [
      {~r/^what(?:'s|s| is| are)\s+the\s+(?:meaning|definition)\s+of\s+(.+?)[\s.?!]*$/iu,
       &definition_tree(text, &1)},
      {~r/^what\s+does\s+(.+?)\s+mean[\s.?!]*$/iu, &definition_tree(text, &1)},
      {~r/^(?:please\s+)?(?:define|describe)\s+(.+?)[\s.?!]*$/iu,
       &definition_tree(text, &1, imperative: true)},
      {~r/^(who|where|when|why|how)(?:'s| is| are| was| were)\s+(.+?)[\s.?!]*$/iu,
       &wh_copula_tree(text, &1)},
      {~r/^what(?:'s|s| is| are)\s+(.+?)[\s.?!]*$/iu, &definition_tree(text, &1)},
      {~r/^(?:is|are|was|were|am)\s+(.+?)[\s.?!]*$/iu, &copula_question_tree(text, &1)}
    ]

    Enum.find_value(constructions, :no_match, fn {regex, builder} ->
      case Regex.run(regex, text, return: :index) do
        nil -> nil
        [_full | captures] -> builder.(captures)
      end
    end)
  end

  # "What is the meaning of X?" / "Define X" -> ACTION_DEFINE, theme X.
  defp definition_tree(text, [theme_idx], opts \\ []) do
    imperative = Keyword.get(opts, :imperative, false)
    theme = phrase_argument(text, theme_idx, "theme")

    unit =
      cond do
        imperative and not String.ends_with?(text, "?") -> "command"
        true -> "question"
      end

    {:ok, tree(@define, unit, List.wrap(theme), 0.9)}
  end

  # "Where is Alice?" -> question, STATE_BE(theme Alice) + focus(location).
  defp wh_copula_tree(text, [wh_idx, theme_idx]) do
    {wh_start, wh_len} = wh_idx
    wh_word = text |> binary_part(wh_start, wh_len) |> String.downcase()
    theme = phrase_argument(text, theme_idx, "theme")

    focus = %{
      "role" => "focus",
      "kind" => "literal",
      "label" => binary_part(text, wh_start, wh_len),
      "canonical" => Map.fetch!(@wh_focus, wh_word),
      "span" => [wh_start, wh_start + wh_len]
    }

    {:ok, tree(@be, "question", List.wrap(theme) ++ [focus], 0.85)}
  end

  # "Is the world green?" -> question, STATE_BE(theme world, attribute green).
  defp copula_question_tree(text, [complement_idx]) do
    {start, len} = complement_idx
    tokens = tokenize_region(text, start, len)

    {theme_tokens, attribute_tokens} = split_copula_complement(tokens)

    args =
      [
        tokens_argument(text, theme_tokens, "theme"),
        tokens_argument(text, attribute_tokens, "attribute")
      ]
      |> Enum.reject(&is_nil/1)

    if args == [] do
      nil
    else
      {:ok, tree(@be, "question", args, 0.85)}
    end
  end

  # Theme = determiner-led noun (or pronoun); everything after is the
  # predicate complement: "the world | green", "she | a student".
  defp split_copula_complement(tokens) do
    case tokens do
      [{det, _, _, _} = d, noun | rest] when rest != [] ->
        if det in @determiners do
          {[d, noun], rest}
        else
          {[d], [noun | rest]}
        end

      [only | rest] when rest != [] ->
        {[only], rest}

      _ ->
        {tokens, []}
    end
  end

  # ---- Clause structure: subject / verb / objects -------------------------

  defp parse_clause(text) do
    tokens = word_tokens(text)
    lowers = Enum.map(tokens, &elem(&1, 0))

    {question_marked, working} = strip_leading_modal(tokens)

    case find_main_verb(working) do
      nil ->
        {:error, :no_parse}

      {verb_idx, entry, consumed} ->
        subject_tokens =
          working
          |> Enum.take(verb_idx)
          |> Enum.reject(fn {lower, _, _, _} -> lower in @subject_noise end)

        post_tokens = Enum.drop(working, verb_idx + consumed)
        chunks = chunk_by_prepositions(post_tokens)

        roles = Vocabulary.roles(entry["id"])
        category = entry["category"]
        subject_role = subject_role(category, roles)
        object_role = object_role(roles, subject_role)

        subject_arg = tokens_argument(text, subject_tokens, subject_role)

        {_, object_args} =
          Enum.reduce(chunks, {false, []}, fn {prep, toks}, {object_used, acc} ->
            {role, object_used} =
              case prep do
                nil when not object_used -> {object_role, true}
                nil -> {"theme", object_used}
                prep -> {Map.fetch!(@prep_roles, prep), object_used}
              end

            case tokens_argument(text, toks, role) do
              nil -> {object_used, acc}
              arg -> {object_used, acc ++ [arg]}
            end
          end)

        args = List.wrap(subject_arg) ++ object_args

        unit =
          cond do
            question_marked or String.ends_with?(String.trim(text), "?") -> "question"
            List.first(lowers) in @wh -> "question"
            subject_arg == nil and category in ["ACT", "EVT"] -> "command"
            true -> "statement"
          end

        confidence =
          0.7 +
            if(subject_arg != nil or subject_tokens == [], do: 0.05, else: 0.0) +
            if(object_args != [], do: 0.1, else: 0.0)

        {:ok, tree(entry, unit, args, Float.round(confidence, 2))}
    end
  end

  defp strip_leading_modal(tokens) do
    case tokens do
      [{lower, _, _, _} | rest] when rest != [] ->
        cond do
          lower == "please" -> strip_leading_modal(rest)
          lower in @modals -> {true, rest}
          true -> {false, tokens}
        end

      _ ->
        {false, tokens}
    end
  end

  # Morphological analysis + verb discovery: the lexicon maps every inflected
  # form to its lemma's vocabulary entry, so "registered" and "joins" resolve
  # exactly like their base forms. Phrasal verbs ("sign up") are tried first.
  defp find_main_verb(tokens) do
    indexed = Enum.with_index(tokens)

    primary =
      Enum.find_value(indexed, fn {{lower, _, _, _}, idx} ->
        if lower in @aux do
          nil
        else
          next = Enum.at(tokens, idx + 1)

          phrasal =
            case next do
              {next_lower, _, _, _} -> Lexicon.lookup(lower <> " " <> next_lower)
              nil -> nil
            end

          cond do
            verb_entry?(phrasal) -> {idx, phrasal, 2}
            verb_entry?(Lexicon.lookup(lower)) -> {idx, Lexicon.lookup(lower), 1}
            true -> nil
          end
        end
      end)

    primary || possessive_verb(indexed) || copula_verb(indexed)
  end

  defp verb_entry?(%{"category" => category}) when category in ["ACT", "STA", "EVT"], do: true
  defp verb_entry?(_), do: false

  # "have/has/had" as main verb (possession) when no other verb exists.
  defp possessive_verb(indexed) do
    Enum.find_value(indexed, fn {{lower, _, _, _}, idx} ->
      if lower in ["have", "has", "had"], do: {idx, @have, 1}
    end)
  end

  # Copula as main verb: "The sky is blue." -> STATE_BE.
  defp copula_verb(indexed) do
    Enum.find_value(indexed, fn {{lower, _, _, _}, idx} ->
      if lower in @copulas, do: {idx, @be, 1}
    end)
  end

  defp chunk_by_prepositions(tokens) do
    tokens
    |> Enum.reduce([], fn {lower, _, _, _} = tok, acc ->
      cond do
        Map.has_key?(@prep_roles, lower) -> [{lower, []} | acc]
        acc == [] -> [{nil, [tok]}]
        true ->
          [{prep, toks} | rest] = acc
          [{prep, toks ++ [tok]} | rest]
      end
    end)
    |> Enum.reverse()
    |> Enum.reject(fn {_prep, toks} -> toks == [] end)
  end

  # The subject of an action is its agent; for states/events the subject is
  # the predicate's first declared role (experiencer, patient, theme...).
  defp subject_role("ACT", _roles), do: "agent"
  defp subject_role(_category, roles), do: List.first(roles) || "agent"

  defp object_role(roles, subject_role) do
    Enum.find(roles, fn role -> role != subject_role and role != "agent" end) || "theme"
  end

  # ---- Pack-driven clause parsing (fr, rw, ...) ---------------------------
  #
  # Verb discovery through the pack's verb map, with morphological prefix
  # stripping declared by the pack: "nshaka" -> n- (REF_SPEAKER) + "shaka"
  # (STATE_WANT). Only the mapped verb touches the vocabulary.

  defp parse_pack(text, locale) do
    verb_map = LanguagePack.Registry.verb_map(locale)
    pronoun_map = LanguagePack.Registry.pronoun_map(locale)
    detection = LanguagePack.Registry.detection(locale)

    tokens = word_tokens(text)

    case find_pack_verb(tokens, verb_map, detection) do
      nil ->
        {:error, :no_parse}

      {idx, entry, prefix_ref} ->
        subject_arg = pack_subject(tokens, idx, pronoun_map, prefix_ref)
        post = Enum.drop(tokens, idx + 1)

        roles = Vocabulary.roles(entry["id"])
        category = Vocabulary.category(entry["id"]) || "ACT"
        subject_role = subject_role(category, roles)
        object_role = object_role(roles, subject_role)

        subject_arg = if subject_arg, do: Map.put(subject_arg, "role", subject_role)
        object_arg = pack_object(text, post, pronoun_map, object_role)

        unit =
          cond do
            String.ends_with?(String.trim(text), "?") -> "question"
            idx == 0 and subject_arg == nil and category == "ACT" -> "command"
            true -> "statement"
          end

        args = List.wrap(subject_arg) ++ List.wrap(object_arg)
        entry = Map.put(entry, "category", category)
        {:ok, tree(entry, unit, args, 0.75)}
    end
  end

  defp find_pack_verb(tokens, verb_map, detection) do
    prefixes =
      detection
      |> Map.get("strip_prefixes", [])
      |> Enum.sort_by(&(-String.length(&1)))

    subject_prefixes = Map.get(detection, "subject_prefixes", %{})

    tokens
    |> Enum.with_index()
    |> Enum.find_value(fn {{lower, _, _, _}, idx} ->
      case Map.get(verb_map, lower) do
        %{"id" => _} = entry ->
          {idx, entry, nil}

        _ ->
          Enum.find_value(prefixes, fn prefix ->
            rest = String.replace_prefix(lower, prefix, "")

            with true <- rest != lower and String.length(rest) > 1,
                 %{"id" => _} = entry <- Map.get(verb_map, rest) do
              {idx, entry, Map.get(subject_prefixes, prefix)}
            else
              _ -> nil
            end
          end)
      end
    end)
  end

  defp pack_subject(tokens, verb_idx, pronoun_map, prefix_ref) do
    explicit =
      tokens
      |> Enum.take(verb_idx)
      |> Enum.find_value(fn {lower, surface, start, stop} ->
        case Map.get(pronoun_map, lower) do
          nil -> nil
          ref -> %{"kind" => "pronoun", "label" => surface, "ref" => ref, "span" => [start, stop]}
        end
      end)

    cond do
      explicit -> explicit
      prefix_ref ->
        {_, surface, start, stop} = Enum.at(tokens, verb_idx)
        %{"kind" => "pronoun", "label" => surface, "ref" => prefix_ref, "span" => [start, stop]}

      true ->
        nil
    end
  end

  defp pack_object(text, tokens, pronoun_map, role) do
    case tokens do
      [] ->
        nil

      [{lower, surface, start, stop}] ->
        case Map.get(pronoun_map, lower) do
          nil -> tokens_argument(text, tokens, role)
          ref -> %{"role" => role, "kind" => "pronoun", "label" => surface, "ref" => ref, "span" => [start, stop]}
        end

      _ ->
        tokens_argument(text, tokens, role)
    end
  end

  # ---- shared helpers ------------------------------------------------------

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

  defp tokenize_region(text, offset, len) do
    text
    |> binary_part(offset, len)
    |> word_tokens()
    |> Enum.map(fn {lower, surface, start, stop} ->
      {lower, surface, start + offset, stop + offset}
    end)
  end

  defp phrase_argument(text, {start, len}, role) do
    tokens_argument(text, tokenize_region(text, start, len), role)
  end

  defp tokens_argument(_text, [], _role), do: nil

  defp tokens_argument(text, tokens, role) do
    kept = Enum.drop_while(tokens, fn {lower, _, _, _} -> lower in @determiners end)
    kept = if kept == [], do: tokens, else: kept

    {_, _, first_start, _} = List.first(kept)
    {_, _, _, last_stop} = List.last(kept)
    surface = binary_part(text, first_start, last_stop - first_start)

    ref =
      case kept do
        [{lower, _, _, _}] ->
          case Lexicon.lookup(lower) do
            %{"ref" => ref} -> ref
            _ -> nil
          end

        _ ->
          nil
      end

    if ref do
      %{"role" => role, "kind" => "pronoun", "label" => surface, "ref" => ref, "span" => [first_start, last_stop]}
    else
      kind = if Enum.any?(kept, &capitalized?/1), do: "named", else: "literal"
      %{"role" => role, "kind" => kind, "label" => surface, "span" => [first_start, last_stop]}
    end
  end

  defp capitalized?({_, surface, _, _}) do
    case String.first(surface) do
      nil -> false
      first -> String.match?(first, ~r/^\p{Lu}$/u)
    end
  end
end
