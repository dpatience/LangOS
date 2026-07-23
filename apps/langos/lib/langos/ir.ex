defmodule LangOS.IR do
  @moduledoc """
  Semantic IR v1.2 — graph-based validation and helpers.
  The graph is the meaning. JSON is serialization.
  """

  @version "1.2"

  @valid_utterance_types ~w(command question statement exclamation fragment)
  @valid_node_types ~w(predicate concept reference)

  @spec validate(map()) :: :ok | {:error, {:invalid_ir, list()}}
  def validate(ir) when is_map(ir) do
    errors =
      []
      |> check_version(ir)
      |> check_source(ir)
      |> check_graph(ir)
      |> check_mentions(ir)
      |> check_utterance_type(ir)
      |> check_confidence(ir)
      |> check_meta(ir)

    if errors == [], do: :ok, else: {:error, {:invalid_ir, Enum.reverse(errors)}}
  end

  @spec version() :: String.t()
  def version, do: @version

  defp check_version(errors, %{"version" => @version}), do: errors
  defp check_version(errors, %{"version" => v}), do: ["version must be #{@version}, got #{v}" | errors]
  defp check_version(errors, _), do: ["missing version" | errors]

  defp check_source(errors, %{"source" => %{"language" => _, "text" => _}}), do: errors
  defp check_source(errors, _), do: ["missing or invalid source" | errors]

  defp check_graph(errors, %{"graph" => %{"nodes" => nodes, "edges" => edges}})
       when is_list(nodes) and is_list(edges) do
    node_errors =
      nodes
      |> Enum.with_index()
      |> Enum.reduce([], fn {node, idx}, acc ->
        cond do
          not is_map(node) -> ["graph.nodes[#{idx}] must be a map" | acc]
          not Map.has_key?(node, "id") -> ["graph.nodes[#{idx}] missing id" | acc]
          not Map.has_key?(node, "type") -> ["graph.nodes[#{idx}] missing type" | acc]
          node["type"] not in @valid_node_types -> ["graph.nodes[#{idx}] invalid type: #{node["type"]}" | acc]
          true -> acc
        end
      end)

    edge_errors =
      edges
      |> Enum.with_index()
      |> Enum.reduce([], fn {edge, idx}, acc ->
        required = ~w(from to role)
        missing = Enum.filter(required, &(not Map.has_key?(edge, &1)))
        if missing == [], do: acc, else: ["graph.edges[#{idx}] missing: #{Enum.join(missing, ", ")}" | acc]
      end)

    node_errors ++ edge_errors ++ errors
  end

  defp check_graph(errors, _), do: ["missing or invalid graph (need nodes + edges)" | errors]

  defp check_mentions(errors, %{"mentions" => mentions}) when is_list(mentions), do: errors
  defp check_mentions(errors, _), do: ["mentions must be a list" | errors]

  defp check_utterance_type(errors, %{"utterance_type" => t}) when t in @valid_utterance_types, do: errors
  defp check_utterance_type(errors, %{"utterance_type" => t}), do: ["invalid utterance_type: #{t}" | errors]
  defp check_utterance_type(errors, _), do: ["missing utterance_type" | errors]

  defp check_confidence(errors, %{"confidence" => %{"overall" => _}}), do: errors
  defp check_confidence(errors, _), do: ["missing confidence.overall" | errors]

  defp check_meta(errors, %{"meta" => %{"engine" => e}}) when is_map(e), do: errors
  defp check_meta(errors, %{"meta" => %{"detected_language" => _}}), do: errors
  defp check_meta(errors, _), do: ["meta must have engine or detected_language" | errors]
end
