defmodule LangOSGoldenTest do
  @moduledoc false
  use ExUnit.Case, async: false
  @moduletag :golden

  @packs ~w(en fr rw tr)

  for pack <- @packs do
    @pack pack
    test "#{pack} golden corpus — v1.2 graph-based IR with vocab IDs" do
      golden_file = Path.expand("../../../packs/#{@pack}/tests/golden.jsonl", __DIR__)

      golden_file
      |> File.read!()
      |> String.split("\n", trim: true)
      |> Enum.each(fn line ->
        %{"input" => input, "expected" => expected} = Jason.decode!(line)

        assert {:ok, resp} = LangOS.understand(input)
        ir = resp["ir"]
        assert ir["version"] == "1.2", "expected v1.2 for: #{input["text"]}"

        assert ir["utterance_type"] == expected["utterance_type"],
               "wrong utterance_type for: #{input["text"]}"

        nodes = ir["graph"]["nodes"]
        edges = ir["graph"]["edges"]
        mentions = ir["mentions"]

        pred_node = Enum.find(nodes, &(&1["type"] == "predicate"))

        assert pred_node["predicate"]["id"] == expected["vocab_id"],
               "expected vocab_id #{expected["vocab_id"]}, got #{pred_node["predicate"]["id"]} for: #{input["text"]}"

        assert pred_node["predicate"]["symbol"] == expected["symbol"],
               "expected symbol #{expected["symbol"]}, got #{pred_node["predicate"]["symbol"]} for: #{input["text"]}"

        for exp_role <- expected["roles"] || [] do
          edge = Enum.find(edges, fn e -> e["role"] == exp_role["role"] end)
          assert edge != nil, "missing edge with role #{exp_role["role"]} for: #{input["text"]}"

          mention = Enum.find(mentions, fn m -> m["surface"] == exp_role["surface"] end)

          assert mention != nil,
                 "missing mention for surface '#{exp_role["surface"]}' in: #{input["text"]}"

          assert mention["node_id"] == edge["to"],
                 "mention node_id doesn't match edge target for role #{exp_role["role"]} in: #{input["text"]}"
        end
      end)
    end
  end
end
