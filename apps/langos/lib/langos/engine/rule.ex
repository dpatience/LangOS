defmodule LangOS.Engine.Rule do
  @moduledoc """
  Rule-based inference engine.
  Parses via language pack patterns (Rust NIF or Elixir fallback).
  Produces v1.2 graph-based IR: predicates as nodes, relationships as edges, concepts and mentions separated.
  """
  use LangOS.Engine

  alias LangOS.{LanguagePack, Native, SemanticGraph}

  @engine_info %{"parser" => "rule", "language_pack" => "en", "version" => "1.0.0"}

  @impl true
  def capabilities, do: [:tokenize, :parse, :extract, :generate, :detect_language]

  @impl true
  def health, do: :ok

  @impl true
  def tokenize(text, _opts), do: Native.safe_tokenize(text)

  @impl true
  def parse(text, opts) do
    locale = Keyword.get(opts, :locale, "en")

    with {:ok, json} <- LanguagePack.Registry.patterns_json(locale),
         {:ok, match} <- Native.safe_parse_patterns(text, json) do
      if match, do: {:ok, match}, else: {:error, :no_match}
    else
      {:error, :not_found} -> {:error, :pack_not_found}
      err -> err
    end
  end

  @impl true
  def extract_meaning(parse_tree, opts) do
    locale = Keyword.get(opts, :locale, "en")
    text = Keyword.get(opts, :text, "")

    vocab_id = parse_tree["vocab_id"]
    symbol = parse_tree["symbol"]
    unit_type = parse_tree["unit_type"] || "command"
    arguments = parse_tree["arguments"] || []

    confidence = %{
      "overall" => parse_tree["confidence"] || 0.97,
      "predicate" => 0.99,
      "roles" => 0.95,
      "references" => 1.0
    }

    engine = Map.put(@engine_info, "language_pack", locale)

    case Native.safe_build_ir(
           language: locale,
           text: text,
           vocab_id: vocab_id,
           symbol: symbol,
           unit_type: unit_type,
           arguments: arguments,
           confidence: confidence,
           engine: engine
         ) do
      {:ok, ir} -> {:ok, ir}
      {:error, _} -> build_elixir_ir(locale, text, parse_tree, engine)
    end
  end

  @impl true
  # IR-driven expression wins over plain templates: translate sends both an
  # "ir" and the "ir_summary" template name, and the data comes from the IR.
  def generate(%{"ir" => ir} = request, opts) when is_map(ir) do
    locale = Map.get(request, "locale") || Keyword.get(opts, :locale, "en")
    template = Map.get(request, "template", "ir_summary")
    summary = summarize_ir(ir)
    express_template_or_default(locale, template, summary)
  end

  def generate(%{"template" => template} = request, opts) do
    locale = Map.get(request, "locale") || Keyword.get(opts, :locale, "en")
    data = Map.get(request, "data", %{})
    tone = Map.get(request, "tone", "neutral")

    with {:ok, template_def} <- LanguagePack.Registry.express_template(locale, template) do
      {:ok, render_template(template_def, data, tone)}
    else
      {:error, :enoent} -> {:error, {:unknown_template, template}}
      err -> err
    end
  end

  def generate(_request, _opts), do: {:error, :missing_template}

  defp express_template_or_default(locale, template, data) do
    case LanguagePack.Registry.express_template(locale, template) do
      {:ok, template_def} -> {:ok, render_template(template_def, data, "neutral")}
      _ -> {:ok, Map.get(data, "summary", "Done.")}
    end
  end

  # Build a human-readable English sentence from the semantic graph.
  # Maps semantic roles to a natural English surface form so translations and
  # ir_summary templates produce readable text rather than symbol notation.
  defp summarize_ir(%{"graph" => %{"nodes" => nodes, "edges" => edges}, "source" => source}) do
    pred = Enum.find(nodes, fn n -> n["type"] == "predicate" end)
    symbol = get_in(pred || %{}, ["predicate", "symbol"]) || "UNKNOWN"
    pred_id = (pred || %{})["id"]

    node_index = Map.new(nodes, fn n -> {n["id"], n} end)

    role_map =
      Enum.reduce(edges, %{}, fn %{"role" => role, "to" => to}, acc ->
        node = Map.get(node_index, to)
        label = node_label(node)
        # Keep only the first filler per role (avoid duplicating coords).
        Map.put_new(acc, role, label)
      end)

    sentence = build_sentence(symbol, pred_id, role_map, source["language"] || "en")
    %{"summary" => sentence}
  end

  defp summarize_ir(%{"source" => %{"text" => text}}) when is_binary(text), do: %{"summary" => text}
  defp summarize_ir(_), do: %{"summary" => "Done."}

  defp node_label(%{"type" => "reference", "reference" => %{"ref" => ref}}) do
    case ref do
      "REF_SPEAKER" -> "I"
      "REF_LISTENER" -> "you"
      "REF_PREVIOUS_ENTITY" -> "it"
      "REF_HERE" -> "here"
      "REF_TIME_NOW" -> "now"
      "REF_TIME_PAST" -> "before"
      "REF_TIME_FUTURE" -> "later"
      _ -> "it"
    end
  end

  defp node_label(%{"type" => "concept", "concept" => %{"canonical" => c}}), do: c
  defp node_label(_), do: nil

  @symbol_verbs %{
    "ACTION_CREATE" => "created",
    "ACTION_DELETE" => "deleted",
    "ACTION_UPDATE" => "updated",
    "ACTION_ASSIGN" => "added",
    "ACTION_REGISTER" => "registered",
    "ACTION_REMOVE" => "removed",
    "ACTION_MOVE" => "moved",
    "ACTION_SEND" => "sent",
    "ACTION_GIVE" => "given",
    "ACTION_SHOW" => "shown",
    "ACTION_LIST" => "listed",
    "ACTION_SEARCH" => "searching for",
    "ACTION_HELP" => "helping",
    "ACTION_START" => "started",
    "ACTION_STOP" => "stopped",
    "ACTION_OPEN" => "opened",
    "ACTION_CLOSE" => "closed",
    "ACTION_READ" => "read",
    "ACTION_WRITE" => "written",
    "ACTION_SAVE" => "saved",
    "ACTION_CONNECT" => "connected",
    "ACTION_DOWNLOAD" => "downloaded",
    "ACTION_UPLOAD" => "uploaded",
    "ACTION_CALL" => "calling",
    "ACTION_EXPLAIN" => "explaining",
    "ACTION_TRANSLATE" => "translated",
    "ACTION_DEFINE" => "defining",
    "ACTION_SUMMARIZE" => "summarizing",
    "ACTION_INVITE" => "invited",
    "ACTION_EAT" => "eating",
    "ACTION_DRINK" => "drinking",
    "ACTION_PLAY" => "playing",
    "ACTION_TRAVEL" => "going to",
    "ACTION_BUY" => "buying",
    "ACTION_PAY" => "paying",
    "ACTION_SLEEP" => "sleeping",
    "STATE_WANT" => "wants",
    "STATE_NEED" => "needs",
    "STATE_KNOW" => "knows",
    "STATE_LOVE" => "loves",
    "STATE_HATE" => "hates",
    "STATE_LIKE" => "likes",
    "STATE_HAVE" => "has",
    "STATE_BE" => "is",
    "STATE_UNDERSTAND" => "understands",
    "STATE_THINK" => "thinks",
    "STATE_FEEL" => "feels",
    "STATE_BELIEVE" => "believes",
    "META_GREET" => "greeting",
    "META_THANK" => "thanking",
    "META_FAREWELL" => "saying goodbye",
    "META_APOLOGIZE" => "apologizing"
  }

  defp build_sentence(symbol, _pred_id, role_map, _locale) do
    verb = Map.get(@symbol_verbs, symbol, String.downcase(symbol))

    agent = role_map["agent"]
    patient = role_map["patient"]
    theme = role_map["theme"]
    goal = role_map["goal"]
    source_role = role_map["source"]
    container = role_map["container"]

    subject = agent || "Someone"
    object = patient || theme

    parts =
      [
        subject,
        verb,
        object,
        container && "in #{container}",
        goal && "to #{goal}",
        source_role && "from #{source_role}"
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" ")

    String.capitalize(parts) <> "."
  end

  defp build_elixir_ir(locale, text, parse_tree, engine) do
    vocab_id = parse_tree["vocab_id"]
    symbol = parse_tree["symbol"]
    unit_type = parse_tree["unit_type"] || "command"
    arguments = parse_tree["arguments"] || []

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
      "overall" => parse_tree["confidence"] || 0.97,
      "predicate" => 0.99,
      "roles" => 0.95,
      "references" => 1.0
    }

    ir = SemanticGraph.to_ir(graph, locale, text, unit_type, confidence, engine)
    {:ok, ir}
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

  defp render_template(%{"patterns" => patterns}, data, tone) when is_list(patterns) do
    # Collect all patterns matching the requested tone; if none match, fall
    # back to neutral, then to all patterns. Pick one at random so callers
    # receive varied phrasing across calls.
    matching =
      Enum.filter(patterns, fn p -> Map.get(p, "tone", "neutral") == tone end)

    fallback =
      if matching == [] do
        neutral = Enum.filter(patterns, fn p -> Map.get(p, "tone", "neutral") == "neutral" end)
        if neutral == [], do: patterns, else: neutral
      else
        matching
      end

    text = fallback |> Enum.random() |> Map.get("text", "")
    interpolate(text, data)
  end

  defp render_template(%{"text" => text}, data, _tone), do: interpolate(text, data)
  defp render_template(_, data, _), do: inspect(data)

  defp interpolate(template, data) when is_binary(template) do
    normalized = normalize_data(data)

    Enum.reduce(normalized, template, fn {key, value}, acc ->
      String.replace(acc, "{{#{key}}}", to_string(value))
    end)
  end

  # Converts map keys to strings and normalises list values to proper English
  # lists with an Oxford comma: ["a", "b", "c"] -> "a, b, and c".
  defp normalize_data(data) when is_map(data) do
    Map.new(data, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), normalize_value(v)}
      {k, v} -> {k, normalize_value(v)}
    end)
  end

  # "a, b, c" (already-formatted comma string) — reformat it as a proper list.
  defp normalize_value(str) when is_binary(str) do
    parts = str |> String.split(~r/\s*,\s*/) |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
    if length(parts) > 1, do: oxford_join(parts), else: str
  end

  defp normalize_value(list) when is_list(list) do
    clean = Enum.map(list, &to_string/1) |> Enum.reject(&(&1 == ""))
    oxford_join(clean)
  end

  defp normalize_value(other), do: other

  # Oxford comma join: "a", ["a", "b"] -> "a and b", ["a","b","c"] -> "a, b, and c"
  defp oxford_join([]), do: ""
  defp oxford_join([only]), do: only
  defp oxford_join([a, b]), do: "#{a} and #{b}"
  defp oxford_join(items) do
    {rest, [last]} = Enum.split(items, length(items) - 1)
    Enum.join(rest, ", ") <> ", and " <> last
  end
end
