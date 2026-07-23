defmodule LangOS do
  @moduledoc """
  LangOS public API — translate human language to Semantic IR and back.
  """

  alias LangOS.Pipeline

  @type understand_request :: map()
  @type express_request :: map()
  @type translate_request :: map()

  @doc """
  Parse human text into Semantic IR.
  """
  @spec understand(understand_request()) :: {:ok, map()} | {:error, term()}
  def understand(request) when is_map(request) do
    Pipeline.understand(request)
  end

  @doc """
  Parse a multi-sentence document into one Semantic IR per semantic unit.
  Units are parsed in parallel; coreference slots carry candidates from
  earlier units.
  """
  @spec understand_document(understand_request()) :: {:ok, map()} | {:error, term()}
  def understand_document(request) when is_map(request) do
    Pipeline.understand_document(request)
  end

  @doc """
  Generate natural language from structured express input.
  """
  @spec express(express_request()) :: {:ok, map()} | {:error, term()}
  def express(request) when is_map(request) do
    Pipeline.express(request)
  end

  @doc """
  Translate text or IR between locales via Semantic IR pivot.
  """
  @spec translate(translate_request()) :: {:ok, map()} | {:error, term()}
  def translate(request) when is_map(request) do
    Pipeline.translate(request)
  end
end
