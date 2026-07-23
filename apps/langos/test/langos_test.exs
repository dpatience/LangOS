defmodule LangOSTest do
  use ExUnit.Case, async: false

  describe "understand/1 — v1.2 graph-based IR" do
    test "register command: predicate is a node, roles are edges, mentions have spans" do
      assert {:ok, resp} =
               LangOS.understand(%{"text" => "Register Clarissa in Biology A1.", "locale" => "en"})

      ir = resp["ir"]
      assert ir["version"] == "1.2"
      assert ir["utterance_type"] == "command"

      graph = ir["graph"]
      nodes = graph["nodes"]
      edges = graph["edges"]
      mentions = ir["mentions"]

      pred_node = Enum.find(nodes, &(&1["type"] == "predicate"))
      assert pred_node["predicate"]["id"] == "ACT_000005"
      assert pred_node["predicate"]["symbol"] == "ACTION_REGISTER"

      assert length(edges) == 2
      roles = Enum.map(edges, & &1["role"])
      assert "patient" in roles
      assert "container" in roles

      assert length(mentions) >= 2
      clarissa_mention = Enum.find(mentions, &(&1["surface"] == "Clarissa"))
      assert clarissa_mention != nil
      assert is_list(clarissa_mention["span"])

      concept_nodes = Enum.filter(nodes, &(&1["type"] == "concept"))
      assert length(concept_nodes) == 2

      assert %{"overall" => _, "predicate" => _, "roles" => _} = ir["confidence"]
      assert is_map(ir["meta"]["engine"])
    end

    test "create command with vocab ID" do
      assert {:ok, resp} =
               LangOS.understand(%{"text" => "Create a student named Alice.", "locale" => "en"})

      pred = Enum.find(resp["ir"]["graph"]["nodes"], &(&1["type"] == "predicate"))
      assert pred["predicate"]["id"] == "ACT_000001"
      assert pred["predicate"]["symbol"] == "ACTION_CREATE"
    end

    test "question: references become reference nodes" do
      assert {:ok, resp} =
               LangOS.understand(%{"text" => "Do you know me?", "locale" => "en"})

      ir = resp["ir"]
      assert ir["utterance_type"] == "question"

      nodes = ir["graph"]["nodes"]
      ref_nodes = Enum.filter(nodes, &(&1["type"] == "reference"))
      assert length(ref_nodes) == 2

      refs = Enum.map(ref_nodes, &get_in(&1, ["reference", "ref"]))
      assert "REF_LISTENER" in refs
      assert "REF_SPEAKER" in refs
    end
  end

  describe "express/1" do
    test "renders missing_fields template" do
      assert {:ok, resp} =
               LangOS.express(%{
                 "template" => "missing_fields",
                 "locale" => "en",
                 "tone" => "formal",
                 "data" => %{"entity" => "Clarissa", "fields" => "age, language, birth date"}
               })

      assert resp["text"] =~ "Clarissa"
      assert resp["text"] =~ "required"
    end
  end

  describe "IR.validate/1 — v1.2" do
    test "accepts valid v1.2 graph-based IR" do
      ir = %{
        "version" => "1.2",
        "source" => %{"language" => "en", "text" => "hi"},
        "graph" => %{
          "nodes" => [%{"id" => "p_1", "type" => "predicate", "predicate" => %{"id" => "META_000001", "symbol" => "META_GREET"}}],
          "edges" => []
        },
        "mentions" => [],
        "utterance_type" => "statement",
        "confidence" => %{"overall" => 0.9},
        "meta" => %{
          "detected_language" => "en",
          "engine" => %{"parser" => "rule", "language_pack" => "en", "version" => "1.0.0"}
        }
      }

      assert :ok = LangOS.IR.validate(ir)
    end

    test "rejects v1.1 IR" do
      ir = %{
        "version" => "1.1",
        "source" => %{"language" => "en", "text" => "hi"},
        "graph" => %{"nodes" => [], "edges" => []},
        "mentions" => [],
        "utterance_type" => "statement",
        "confidence" => %{"overall" => 0.9},
        "meta" => %{"detected_language" => "en", "engine" => %{"parser" => "rule"}}
      }

      assert {:error, {:invalid_ir, _}} = LangOS.IR.validate(ir)
    end

    test "rejects IR without graph" do
      ir = %{
        "version" => "1.2",
        "source" => %{"language" => "en", "text" => "hi"},
        "nodes" => [],
        "mentions" => [],
        "utterance_type" => "statement",
        "confidence" => %{"overall" => 0.9},
        "meta" => %{"detected_language" => "en", "engine" => %{"parser" => "rule"}}
      }

      assert {:error, {:invalid_ir, _}} = LangOS.IR.validate(ir)
    end
  end
end
