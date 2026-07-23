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

  def generate(%{"ir" => ir}, opts) when is_map(ir) do
    locale = Keyword.get(opts, :locale, "en")
    summary = summarize_ir(ir)
    express_template_or_default(locale, "ir_summary", summary)
  end

  def generate(_request, _opts), do: {:error, :missing_template}

  defp express_template_or_default(locale, template, data) do
    case LanguagePack.Registry.express_template(locale, template) do
      {:ok, template_def} -> {:ok, render_template(template_def, data, "neutral")}
      _ -> {:ok, Map.get(data, "summary", "Done.")}
    end
  end

  defp summarize_ir(%{"graph" => %{"nodes" => nodes, "edges" => edges}}) do
    pred = Enum.find(nodes, fn n -> n["type"] == "predicate" end)
    symbol = get_in(pred || %{}, ["predicate", "symbol"]) || "unknown"
    roles = Enum.map(edges, fn e -> e["role"] end) |> Enum.join(", ")
    %{"summary" => "#{symbol}(#{roles})"}
  end

  defp summarize_ir(_), do: %{"summary" => "Done."}

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
    pattern =
      patterns
      |> Enum.find(%{}, fn p -> Map.get(p, "tone", "neutral") == tone end)
      |> case do
        %{"text" => text} -> text
        _ -> patterns |> List.first(%{}) |> Map.get("text", "")
      end

    interpolate(pattern, data)
  end

  defp render_template(%{"text" => text}, data, _tone), do: interpolate(text, data)
  defp render_template(_, data, _), do: inspect(data)

  defp interpolate(template, data) when is_binary(template) do
    Enum.reduce(normalize_data(data), template, fn {key, value}, acc ->
      String.replace(acc, "{{#{key}}}", to_string(value))
    end)
  end

  defp normalize_data(data) when is_map(data) do
    Map.new(data, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), normalize_value(v)}
      {k, v} -> {k, normalize_value(v)}
    end)
  end

  defp normalize_value(list) when is_list(list), do: Enum.join(list, ", ")
  defp normalize_value(other), do: other
end
