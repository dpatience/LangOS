defmodule LangOS.Gateway do
  @moduledoc """
  Request normalization and cache lookup before pipeline execution.
  """
  alias LangOS.Cache

  @spec normalize_understand(map()) :: {:ok, map()} | {:error, term()}
  def normalize_understand(request) do
    text = Map.get(request, "text") || Map.get(request, :text)

    cond do
      is_nil(text) or text == "" ->
        {:error, :missing_text}

      true ->
        # No default here: a missing locale means language detection decides
        # which pack parses. Only explicit request locales act as hints.
        locale = Map.get(request, "locale") || Map.get(request, :locale)

        {:ok,
         %{
           "text" => String.trim(to_string(text)),
           "conversation" => Map.get(request, "conversation", []),
           "entities" => Map.get(request, "entities", []),
           "locale" => locale,
           "options" => Map.get(request, "options", %{})
         }}
    end
  end

  @spec normalize_express(map()) :: {:ok, map()} | {:error, term()}
  def normalize_express(request) do
    locale =
      Map.get(request, "locale") ||
        Map.get(request, :locale) ||
        LangOS.Config.get([:language_packs, :default], "en")

    if Map.has_key?(request, "template") or Map.has_key?(request, "ir") or
         Map.has_key?(request, :template) or Map.has_key?(request, :ir) do
      {:ok,
       request
       |> stringify_keys()
       |> Map.put("locale", locale)}
    else
      {:error, :missing_template_or_ir}
    end
  end

  @spec with_cache(map(), (-> {:ok, map()} | {:error, term()})) ::
          {:ok, map(), :hit | :miss} | {:error, term()}
  def with_cache(request, fun) when is_function(fun, 0) do
    if Application.get_env(:langos, :cache_enabled, true) do
      key = Cache.cache_key(request)

      case Cache.get(key) do
        {:ok, cached} ->
          {:ok, cached, :hit}

        :miss ->
          case fun.() do
            {:ok, response} ->
              Cache.put(key, response)
              {:ok, response, :miss}

            err ->
              err
          end
      end
    else
      case fun.() do
        {:ok, response} -> {:ok, response, :miss}
        err -> err
      end
    end
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), stringify_keys(v)}
      {k, v} -> {k, stringify_keys(v)}
    end)
  end

  defp stringify_keys(other), do: other
end
