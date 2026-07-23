defmodule LangOS.Engine.Neural do
  @moduledoc """
  Bootstrap neural engine for Phase 1 — heuristic parse/generate until models ship.
  Emits graph-based IR with vocab IDs, proper references, and concept/mention separation.
  """
  use LangOS.Engine

  alias LangOS.{Predicates, SemanticGraph}

  @engine_info %{"parser" => "neural_bootstrap", "language_pack" => "en", "version" => "1.0.0"}

  @impl true
  def capabilities, do: [:parse, :extract, :generate]

  @impl true
  def health, do: :ok

  @impl true
  def parse(text, opts) do
    locale = Keyword.get(opts, :locale, "en")
    trimmed = text |> String.trim() |> String.replace(~r/[.!?]+$/, "")

    case infer_command(trimmed, locale) do
      {:ok, result} ->
        {:ok, result}

      :unknown ->
        # Unit type must see the original punctuation ("?" was stripped above).
        {:ok, Map.put(fallback_parse(trimmed), "unit_type", detect_unit_type(String.trim(text)))}
    end
  end

  @impl true
  def extract_meaning(parse_tree, opts) do
    locale = Keyword.get(opts, :locale, "en")
    text = Keyword.get(opts, :text, "")

    vocab_id = parse_tree["vocab_id"]
    symbol = parse_tree["symbol"]
    unit_type = parse_tree["unit_type"] || detect_unit_type(text)
    arguments = parse_tree["arguments"] || []
    engine = Map.put(@engine_info, "language_pack", locale)

    graph = SemanticGraph.new()
    {graph, pred_id} = SemanticGraph.add_predicate_node(graph, vocab_id, symbol)

    graph =
      Enum.reduce(arguments, graph, fn arg, g ->
        role = arg["role"]
        surface = arg["label"] || ""
        kind = arg["kind"] || "named"
        ref = resolve_reference(surface)
        span = arg["span"] || [0, String.length(text)]

        {g2, node_id} =
          if ref do
            SemanticGraph.add_reference_node(g, ref)
          else
            SemanticGraph.add_concept_node(g, String.downcase(surface), kind)
          end

        g2
        |> SemanticGraph.add_edge(pred_id, node_id, role)
        |> SemanticGraph.add_mention(node_id, surface, span)
      end)

    confidence = %{
      "overall" => parse_tree["confidence"] || 0.70,
      "predicate" => 0.75,
      "roles" => 0.70,
      "references" => 1.0
    }

    ir = SemanticGraph.to_ir(graph, locale, text, unit_type, confidence, engine)
    {:ok, ir}
  end

  @impl true
  def generate(request, opts) do
    LangOS.Engine.Rule.generate(request, opts)
  end

  defp infer_command(text, locale) do
    cond do
      match = Regex.run(~r/^(?:please\s+)?create\s+(?:a\s+)?(.+?)\s+(?:named|called)\s+(.+)$/i, text, return: :index) ->
        full = Regex.run(~r/^(?:please\s+)?create\s+(?:a\s+)?(.+?)\s+(?:named|called)\s+(.+)$/i, text) || []
        [_, entity_type, name] = full
        [{_, _}, {s1, l1}, {s2, l2}] = match

        {:ok, %{
           "vocab_id" => "ACT_000001", "symbol" => "ACTION_CREATE", "unit_type" => "command",
           "arguments" => [
             %{"role" => "theme", "kind" => "named", "label" => entity_type, "span" => [s1, s1 + l1]},
             %{"role" => "name", "kind" => "literal", "label" => name, "span" => [s2, s2 + l2]}
           ],
           "span" => [0, String.length(text)], "confidence" => 0.75
         }}

      match = Regex.run(~r/^(?:please\s+)?add\s+(.+?)\s+to\s+(.+)$/i, text, return: :index) ->
        full = Regex.run(~r/^(?:please\s+)?add\s+(.+?)\s+to\s+(.+)$/i, text) || []
        [_, patient, container] = full
        [{_, _}, {s1, l1}, {s2, l2}] = match

        {:ok, %{
           "vocab_id" => "ACT_000004", "symbol" => "ACTION_ASSIGN", "unit_type" => "command",
           "arguments" => [
             %{"role" => "patient", "kind" => "named", "label" => patient, "span" => [s1, s1 + l1]},
             %{"role" => "container", "kind" => "named", "label" => container, "span" => [s2, s2 + l2]}
           ],
           "span" => [0, String.length(text)], "confidence" => 0.75
         }}

      match = Regex.run(~r/^(.+?)\s+is\s+(\d+)\s+years?\s+old$/i, text, return: :index) ->
        full = Regex.run(~r/^(.+?)\s+is\s+(\d+)\s+years?\s+old$/i, text) || []
        [_, subject, age] = full
        [{_, _}, {s1, l1}, {s2, l2}] = match

        {:ok, %{
           "vocab_id" => "STA_000001", "symbol" => "STATE_BE", "unit_type" => "statement",
           "arguments" => [
             %{"role" => "theme", "kind" => "named", "label" => subject, "span" => [s1, s1 + l1]},
             %{"role" => "attribute", "kind" => "quantity", "label" => age, "span" => [s2, s2 + l2]}
           ],
           "span" => [0, String.length(text)], "confidence" => 0.70
         }}

      match = Regex.run(~r/^do\s+you\s+know\s+(.+)$/i, text, return: :index) ->
        full = Regex.run(~r/^do\s+you\s+know\s+(.+)$/i, text) || []
        [_, object] = full
        [{_, _}, {s1, l1}] = match
        you_start = 3

        {:ok, %{
           "vocab_id" => "QRY_000001", "symbol" => "QUERY_KNOW", "unit_type" => "question",
           "arguments" => [
             %{"role" => "experiencer", "kind" => "pronoun", "label" => "you", "ref" => "REF_LISTENER", "span" => [you_start, you_start + 3]},
             %{"role" => "theme", "kind" => ref_kind(object), "label" => object, "ref" => resolve_reference(object), "span" => [s1, s1 + l1]}
           ],
           "span" => [0, String.length(text)], "confidence" => 0.70
         }}

      true ->
        maybe_verb_lookup(text, locale)
    end
  end

  defp maybe_verb_lookup(text, locale) do
    words = String.split(text, ~r/\s+/, parts: 2)

    case words do
      [verb | _] ->
        entry = Predicates.lookup_verb(verb, locale)

        if entry["id"] != "UNK_000001" do
          {:ok, %{
             "vocab_id" => entry["id"], "symbol" => entry["symbol"],
             "unit_type" => detect_unit_type(text),
             "arguments" => [
               %{"role" => "content", "kind" => "literal", "label" => text, "span" => [0, String.length(text)]}
             ],
             "span" => [0, String.length(text)], "confidence" => 0.60
           }}
        else
          :unknown
        end

      _ -> :unknown
    end
  end

  defp fallback_parse(text) do
    %{
      "vocab_id" => "UNK_000001", "symbol" => "UNKNOWN",
      "unit_type" => detect_unit_type(text),
      "arguments" => [
        %{"role" => "content", "kind" => "literal", "label" => text, "span" => [0, String.length(text)]}
      ],
      "span" => [0, String.length(text)], "confidence" => 0.40
    }
  end

  defp detect_unit_type(text) do
    trimmed = String.trim(text)
    cond do
      String.ends_with?(trimmed, "?") -> "question"
      String.ends_with?(trimmed, "!") -> "exclamation"
      Regex.match?(~r/^(do|does|is|are|was|were|can|could|would|will|shall|have|has|did)\s/i, trimmed) -> "question"
      Regex.match?(~r/^(please\s+)?(register|create|add|delete|remove|update|set|show|list|install|move|send|give|start|stop|help)\b/i, trimmed) -> "command"
      true -> "statement"
    end
  end

  defp resolve_reference(label) when is_binary(label) do
    case String.downcase(label) do
      w when w in ~w(me i my mine myself) -> "REF_SPEAKER"
      w when w in ~w(you your yours yourself) -> "REF_LISTENER"
      w when w in ~w(now today) -> "REF_TIME_NOW"
      w when w in ~w(here) -> "REF_HERE"
      _ -> nil
    end
  end

  defp resolve_reference(_), do: nil

  defp ref_kind(label) do
    if resolve_reference(label), do: "pronoun", else: "named"
  end
end
