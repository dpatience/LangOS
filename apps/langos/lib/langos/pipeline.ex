defmodule LangOS.Pipeline do
  @moduledoc """
  Orchestrates understand, express, and translate pipeline stages.
  Pipeline: text → detect language → parse → build graph → export IR v1.2.
  """
  alias LangOS.{Config, Gateway, IR, LanguageDetector, ReferenceMarker, Router, Splitter}

  @spec understand(map()) :: {:ok, map()} | {:error, term()}
  def understand(request) do
    started = System.monotonic_time(:millisecond)

    with {:ok, normalized} <- Gateway.normalize_understand(request),
         {:ok, response, _cache} <-
           Gateway.with_cache(normalized, fn -> run_understand(normalized) end) do
      latency = System.monotonic_time(:millisecond) - started
      {:ok, Map.put(response, "latency_ms", latency)}
    end
  end

  @doc """
  Understand a multi-sentence document.

  The text is split into semantic units, parsed in parallel
  (`Task.async_stream`, bounded by `documents.max_unit_concurrency`), then
  reference-marked sequentially so each unit sees the named entities of the
  units before it (coreference candidates). `on_unit` — when given — is
  called with every finished unit in order, which is how the SSE transport
  streams long documents.
  """
  @spec understand_document(map(), (map() -> any()) | nil) :: {:ok, map()} | {:error, term()}
  def understand_document(request, on_unit \\ nil) do
    started = System.monotonic_time(:millisecond)

    with {:ok, normalized} <- Gateway.normalize_understand(request) do
      units = Splitter.split(normalized["text"])
      concurrency = Config.get(["documents", "max_unit_concurrency"], 4)

      results =
        units
        |> Task.async_stream(
          fn unit ->
            understand(%{"text" => unit["text"], "locale" => normalized["locale"]})
          end,
          max_concurrency: concurrency,
          ordered: true,
          timeout: 30_000
        )
        |> Enum.zip(units)

      {units_out, _entities} =
        results
        |> Enum.with_index()
        |> Enum.map_reduce([], fn {{task_result, unit}, index}, prior ->
          unit_out = document_unit(task_result, unit, index, prior)
          if on_unit, do: on_unit.(unit_out)

          new_entities =
            case unit_out["ir"] do
              nil -> prior
              ir -> ReferenceMarker.named_entities(ir, index) ++ prior
            end

          {unit_out, new_entities}
        end)

      languages = units_out |> Enum.map(& &1["language"]) |> Enum.reject(&is_nil/1)

      language =
        languages
        |> Enum.frequencies()
        |> Enum.max_by(&elem(&1, 1), fn -> {"en", 0} end)
        |> elem(0)

      {:ok,
       %{
         "units" => units_out,
         "unit_count" => length(units_out),
         "language" => language,
         "latency_ms" => System.monotonic_time(:millisecond) - started
       }}
    end
  end

  defp document_unit(task_result, unit, index, prior_entities) do
    base = %{"unit" => index, "text" => unit["text"], "span" => unit["span"]}

    case task_result do
      {:ok, {:ok, resp}} ->
        ir = ReferenceMarker.mark(resp["ir"], prior_entities)

        base
        |> Map.put("ir", ir)
        |> Map.put("language", resp["language"])

      {:ok, {:error, reason}} ->
        Map.put(base, "error", inspect(reason))

      {:exit, reason} ->
        Map.put(base, "error", "unit_timeout: #{inspect(reason)}")
    end
  end

  @spec express(map()) :: {:ok, map()} | {:error, term()}
  def express(request) do
    started = System.monotonic_time(:millisecond)

    with {:ok, normalized} <- Gateway.normalize_express(request),
         {:ok, response, _} <-
           Gateway.with_cache(normalized, fn -> run_express(normalized) end) do
      latency = System.monotonic_time(:millisecond) - started

      {:ok,
       %{
         "text" => response["text"],
         "locale" => normalized["locale"],
         "latency_ms" => latency
       }}
    end
  end

  @spec translate(map()) :: {:ok, map()} | {:error, term()}
  def translate(%{"text" => text, "from" => from, "to" => to}) when is_binary(text) do
    started = System.monotonic_time(:millisecond)

    with {:ok, understand_resp} <- understand(%{"text" => text, "locale" => from}),
         ir <- understand_resp["ir"],
         {:ok, express_resp} <-
           express(%{"ir" => ir, "locale" => to, "template" => "ir_summary"}) do
      latency = System.monotonic_time(:millisecond) - started

      {:ok,
       %{
         "text" => express_resp["text"],
         "ir" => ir,
         "from" => from,
         "to" => to,
         "latency_ms" => latency
       }}
    end
  end

  def translate(%{"ir" => ir, "to" => to}) when is_map(ir) do
    express(%{"ir" => ir, "locale" => to, "template" => "ir_summary"})
  end

  def translate(_), do: {:error, :invalid_translate_request}

  defp run_understand(%{"text" => text} = request) do
    # Stage 1: language detection selects the pack that parses. A request
    # locale is an explicit hint; otherwise every installed pack competes.
    detected = LanguageDetector.detect(text, request["locale"])
    locale = detected

    token_count = Router.token_count(text)
    context = %{text: text, locale: locale, token_count: token_count}

    with {:ok, {mod, tree}} <- parse_with_chain(context, text, locale),
         {:ok, ir} <- mod.extract_meaning(tree, locale: locale, text: text) do
      ir =
        update_in(ir, ["meta"], fn meta ->
          (meta || %{}) |> Map.put("detected_language", detected)
        end)

      case IR.validate(ir) do
        :ok ->
          ir = ReferenceMarker.mark(ir, request["prior_entities"] || [])
          graph = ir["graph"] || %{"nodes" => [], "edges" => []}
          node_count = length(graph["nodes"] || [])
          edge_count = length(graph["edges"] || [])

          {:ok,
           %{
             "ir" => ir,
             "mentions" => ir["mentions"] || [],
             "nodes" => node_count,
             "edges" => edge_count,
             "language" => detected
           }}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp parse_with_chain(context, text, locale) do
    context
    |> Router.parse_chain()
    |> Enum.reduce_while({:error, :no_engine}, fn mod, _acc ->
      case mod.parse(text, locale: locale, text: text) do
        {:ok, tree} -> {:halt, {:ok, {mod, tree}}}
        {:error, _} -> {:cont, {:error, :no_parse}}
      end
    end)
  end

  defp run_express(request) do
    context = %{locale: request["locale"]}

    with {:ok, mod} <- Router.select_engine(:generate, context),
         {:ok, text} <- mod.generate(request, locale: request["locale"]) do
      {:ok, %{"text" => text}}
    end
  end
end
