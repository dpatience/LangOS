defmodule LangOS.SemanticGraph do
  @moduledoc """
  Pure Elixir semantic graph engine.
  Everything is a node. Relationships are edges. JSON IR is a serialization.
  Used when Rust NIF is unavailable or as the canonical Elixir-side builder.
  """

  defstruct nodes: %{}, edges: [], mentions: []

  @type t :: %__MODULE__{
          nodes: %{String.t() => map()},
          edges: [map()],
          mentions: [map()]
        }

  @spec new() :: t()
  def new, do: %__MODULE__{}

  @spec add_predicate_node(t(), String.t(), String.t()) :: {t(), String.t()}
  def add_predicate_node(%__MODULE__{} = g, vocab_id, symbol) do
    id = deterministic_id("pred:#{vocab_id}:#{symbol}", "p")

    node = %{
      "id" => id,
      "type" => "predicate",
      "predicate" => %{"id" => vocab_id, "symbol" => symbol}
    }

    {%{g | nodes: Map.put_new(g.nodes, id, node)}, id}
  end

  @spec add_concept_node(t(), String.t(), String.t()) :: {t(), String.t()}
  def add_concept_node(%__MODULE__{} = g, canonical, kind) do
    id = deterministic_id("concept:#{canonical}:#{kind}", "c")

    node = %{
      "id" => id,
      "type" => "concept",
      "concept" => %{"canonical" => canonical, "kind" => kind}
    }

    {%{g | nodes: Map.put_new(g.nodes, id, node)}, id}
  end

  @spec add_reference_node(t(), String.t()) :: {t(), String.t()}
  def add_reference_node(%__MODULE__{} = g, ref_type) do
    id = deterministic_id("ref:#{ref_type}", "r")

    node = %{
      "id" => id,
      "type" => "reference",
      "reference" => %{"ref" => ref_type}
    }

    {%{g | nodes: Map.put_new(g.nodes, id, node)}, id}
  end

  @spec add_edge(t(), String.t(), String.t(), String.t()) :: t()
  def add_edge(%__MODULE__{} = g, from, to, role) do
    edge = %{"from" => from, "to" => to, "role" => role}
    %{g | edges: g.edges ++ [edge]}
  end

  @spec add_mention(t(), String.t(), String.t(), list()) :: t()
  def add_mention(%__MODULE__{} = g, node_id, surface, span) do
    mention = %{"node_id" => node_id, "surface" => surface, "span" => span}
    %{g | mentions: g.mentions ++ [mention]}
  end

  @spec to_ir(t(), String.t(), String.t(), String.t(), map(), map()) :: map()
  def to_ir(%__MODULE__{} = g, language, text, utterance_type, confidence, engine) do
    %{
      "version" => "1.2",
      "source" => %{"language" => language, "text" => text},
      "graph" => %{
        "nodes" => Map.values(g.nodes),
        "edges" => g.edges
      },
      "mentions" => g.mentions,
      "utterance_type" => utterance_type,
      "confidence" => confidence,
      "meta" => %{
        "detected_language" => language,
        "engine" => engine
      }
    }
  end

  defp deterministic_id(seed, prefix) do
    hash =
      :crypto.hash(:sha256, seed)
      |> Base.encode16(case: :lower)
      |> binary_part(0, 16)

    "#{prefix}_#{hash}"
  end
end
