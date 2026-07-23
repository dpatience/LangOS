defmodule LangOS.ReferenceMarker do
  @moduledoc """
  Coreference marking — slots, not resolution.

  LangOS never resolves who "she" is; that requires application state.
  Instead, every reference node in the graph is annotated with a stable
  *slot* the application can fill, and — for discourse references such as
  REF_PREVIOUS_ENTITY — with ranked candidates gathered from earlier
  semantic units of the same document or conversation.

      "Register Clarissa. She starts Monday."
        unit 2: REF_PREVIOUS_ENTITY -> slot "previous_entity",
                candidates: [clarissa (unit 1)]

  The output lives under `ir["references"]`; the graph itself is untouched,
  so the IR stays immutable and v1.2-valid.
  """

  @slots %{
    "REF_SPEAKER" => "speaker",
    "REF_LISTENER" => "listener",
    "REF_PREVIOUS_ENTITY" => "previous_entity",
    "REF_PREVIOUS_ACTION" => "previous_action",
    "REF_TIME_NOW" => "time_now",
    "REF_TIME_PAST" => "time_past",
    "REF_TIME_FUTURE" => "time_future",
    "REF_HERE" => "location_here",
    "REF_CONTEXT" => "context"
  }

  @discourse_slots ["previous_entity", "previous_action"]

  @doc """
  Annotate every reference node with its coreference slot.
  `prior_entities` are named concepts from earlier units, most recent first.
  """
  @spec mark(map(), [map()]) :: map()
  def mark(ir, prior_entities \\ []) do
    references =
      ir
      |> get_in(["graph", "nodes"])
      |> List.wrap()
      |> Enum.filter(&(&1["type"] == "reference"))
      |> Enum.map(fn node ->
        ref = get_in(node, ["reference", "ref"])
        slot = Map.get(@slots, ref, "context")

        entry = %{
          "node_id" => node["id"],
          "ref" => ref,
          "slot" => slot,
          "resolution" => "deferred"
        }

        if slot in @discourse_slots and prior_entities != [] do
          Map.put(entry, "candidates", Enum.take(prior_entities, 5))
        else
          entry
        end
      end)

    Map.put(ir, "references", references)
  end

  @doc """
  Named concepts of an IR, for use as coreference candidates in later units.
  """
  @spec named_entities(map(), non_neg_integer()) :: [map()]
  def named_entities(ir, unit_index \\ 0) do
    ir
    |> get_in(["graph", "nodes"])
    |> List.wrap()
    |> Enum.filter(fn node ->
      node["type"] == "concept" and get_in(node, ["concept", "kind"]) != "literal"
    end)
    |> Enum.map(fn node ->
      %{
        "canonical" => get_in(node, ["concept", "canonical"]),
        "kind" => get_in(node, ["concept", "kind"]),
        "node_id" => node["id"],
        "unit" => unit_index
      }
    end)
  end
end
