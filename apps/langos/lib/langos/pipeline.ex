defmodule LangOS.Pipeline do
  @moduledoc """
  Orchestrates understand, express, and translate pipeline stages.
  Pipeline: text → detect language → parse → build graph → export IR v1.2.
  """
  alias LangOS.{Gateway, IR, Native, Router}

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
    locale = request["locale"]
    token_count = Router.token_count(text)
    context = %{text: text, locale: locale, token_count: token_count}

    with detected <- Native.safe_detect_language(text, locale),
         {:ok, {mod, tree}} <- parse_with_chain(context, text, locale),
         {:ok, ir} <- mod.extract_meaning(tree, locale: locale, text: text) do
      ir =
        update_in(ir, ["meta"], fn meta ->
          (meta || %{}) |> Map.put("detected_language", detected)
        end)

      case IR.validate(ir) do
        :ok ->
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
