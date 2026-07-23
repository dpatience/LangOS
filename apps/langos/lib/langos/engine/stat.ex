defmodule LangOS.Engine.Stat do
  @moduledoc """
  Statistical engine — LangOS-owned trained model, no external APIs.

  Uses the Naive Bayes intent classifier trained by python/langos_train
  (unigram + bigram features, uniform priors, shared-vocabulary Laplace
  smoothing) to map free-form utterances onto vocabulary IDs, and the
  Lexicon to extract reference arguments (pronouns/deictics) with spans.
  """
  use LangOS.Engine

  alias LangOS.{Config, Lexicon, Model, Native, SemanticGraph}

  @engine_info %{"parser" => "stat_naive_bayes", "language_pack" => "en", "version" => "1.0.0"}

  @word_regex ~r/[a-z0-9']+/u

  @impl true
  def capabilities, do: [:parse, :extract, :detect_language]

  @impl true
  def health do
    if Model.intent("en"), do: :ok, else: {:error, :model_not_loaded}
  end

  @impl true
  def parse(text, opts) do
    locale = Keyword.get(opts, :locale, "en")

    case Model.intent(model_locale(locale)) do
      nil ->
        {:error, :model_not_loaded}

      model ->
        trimmed = String.trim(text)

        case classify(trimmed, model) do
          {vocab_id, symbol, confidence} ->
            threshold = min_confidence()

            if confidence >= threshold do
              {:ok, build_parse_tree(trimmed, locale, vocab_id, symbol, confidence)}
            else
              {:error, :low_confidence}
            end

          nil ->
            {:error, :no_classification}
        end
    end
  end

  @impl true
  def extract_meaning(parse_tree, opts) do
    locale = Keyword.get(opts, :locale, "en")
    text = Keyword.get(opts, :text, "")

    vocab_id = parse_tree["vocab_id"]
    symbol = parse_tree["symbol"]
    unit_type = parse_tree["unit_type"] || "statement"
    arguments = parse_tree["arguments"] || []
    engine = Map.put(@engine_info, "language_pack", locale)

    graph = SemanticGraph.new()
    {graph, pred_id} = SemanticGraph.add_predicate_node(graph, vocab_id, symbol)

    graph =
      Enum.reduce(arguments, graph, fn arg, g ->
        role = arg["role"]
        surface = arg["label"] || ""
        kind = arg["kind"] || "named"
        span = arg["span"] || [0, String.length(text)]

        {g2, node_id} =
          if arg["ref"] do
            SemanticGraph.add_reference_node(g, arg["ref"])
          else
            SemanticGraph.add_concept_node(g, String.downcase(surface), kind)
          end

        g2
        |> SemanticGraph.add_edge(pred_id, node_id, role)
        |> SemanticGraph.add_mention(node_id, surface, span)
      end)

    confidence = %{
      "overall" => parse_tree["confidence"] || 0.5,
      "predicate" => parse_tree["confidence"] || 0.5,
      "roles" => 0.6,
      "references" => 1.0
    }

    {:ok, SemanticGraph.to_ir(graph, locale, text, unit_type, confidence, engine)}
  end

  @doc "Locale-aware language detection (kept from Phase 1)."
  def detect_language(text, locale) do
    Native.safe_detect_language(text, locale)
  end

  # ---- classification --------------------------------------------------

  @doc """
  Score all classes with Naive Bayes and return {vocab_id, symbol, confidence}.

  Confidence = top1-vs-top2 margin (pairwise sigmoid) x feature hit rate
  (fraction of the utterance's features known to the winning class).
  Softmax over hundreds of correlated classes is too flat to threshold;
  this measure cleanly separates correct parses from noise: gibberish
  scores 0.0 because the winning class knows none of its features.
  """
  def classify(text, model) do
    feats = features(text)
    classes = model["classes"]

    scores =
      Enum.map(classes, fn {vid, class} ->
        likelihoods = class["log_likelihood"]
        default = class["log_default"]

        score =
          class["log_prior"] +
            Enum.reduce(feats, 0.0, fn f, acc ->
              acc + Map.get(likelihoods, f, default)
            end)

        {vid, score}
      end)

    case Enum.sort_by(scores, &elem(&1, 1), :desc) do
      [] ->
        nil

      [{best_vid, best_score} | rest] ->
        margin_conf =
          case rest do
            [{_, second_score} | _] -> 1.0 / (1.0 + :math.exp(second_score - best_score))
            [] -> 1.0
          end

        likelihoods = classes[best_vid]["log_likelihood"]

        hit_rate =
          case feats do
            [] -> 0.0
            _ -> Enum.count(feats, &Map.has_key?(likelihoods, &1)) / length(feats)
          end

        confidence = Float.round(margin_conf * hit_rate, 4)
        {best_vid, classes[best_vid]["symbol"], confidence}
    end
  end

  defp features(text) do
    tokens = Regex.scan(@word_regex, String.downcase(text)) |> Enum.map(&hd/1)
    bigrams = tokens |> Enum.chunk_every(2, 1, :discard) |> Enum.map(&Enum.join(&1, "_"))
    tokens ++ bigrams
  end

  # ---- argument extraction ----------------------------------------------

  defp build_parse_tree(text, locale, vocab_id, symbol, confidence) do
    references =
      text
      |> Lexicon.annotate_words(locale)
      |> Enum.filter(fn m -> m["entry"]["ref"] end)

    category = String.slice(vocab_id, 0, 3)
    arguments = reference_arguments(references, category)

    arguments =
      if arguments == [] do
        content = String.replace(text, ~r/[.!?]+$/, "")
        [%{"role" => "content", "kind" => "literal", "label" => content, "span" => [0, String.length(content)]}]
      else
        arguments
      end

    %{
      "vocab_id" => vocab_id,
      "symbol" => symbol,
      "unit_type" => detect_unit_type(text),
      "arguments" => arguments,
      "span" => [0, String.length(text)],
      "confidence" => confidence
    }
  end

  defp reference_arguments(references, category) do
    first_role = if category in ["QRY", "STA"], do: "experiencer", else: "agent"

    references
    |> Enum.with_index()
    |> Enum.map(fn {m, idx} ->
      %{
        "role" => if(idx == 0, do: first_role, else: "theme"),
        "kind" => "pronoun",
        "label" => m["surface"],
        "ref" => m["entry"]["ref"],
        "span" => m["span"]
      }
    end)
  end

  defp detect_unit_type(text) do
    trimmed = String.trim(text)

    cond do
      String.ends_with?(trimmed, "?") -> "question"
      String.ends_with?(trimmed, "!") -> "exclamation"
      Regex.match?(~r/^(do|does|is|are|was|were|can|could|would|will|shall|have|has|did|who|what|where|when|why|how|which|whose)\s/i, trimmed) -> "question"
      imperative?(trimmed) -> "command"
      true -> "statement"
    end
  end

  # Imperative: the sentence starts with an action verb ("delete the files",
  # "please summarize the report") rather than a subject.
  defp imperative?(text) do
    first_word =
      text
      |> String.downcase()
      |> String.replace_prefix("please ", "")
      |> String.split(~r/\s+/, parts: 2)
      |> List.first()

    case first_word && Lexicon.lookup(first_word) do
      %{"category" => "ACT"} -> true
      _ -> false
    end
  end

  defp model_locale(locale) do
    if Model.intent(locale), do: locale, else: "en"
  end

  defp min_confidence do
    case Process.whereis(Config) do
      nil -> 0.30
      _ -> Config.get(["engines", "stat", "min_confidence"], 0.30)
    end
  end
end
