defmodule LangOSPhase3Test do
  @moduledoc """
  Phase 3 platform features: splitter, document pipeline with coreference
  slots, vocabulary plugins, per-stage routing, benchmark harness, and the
  MCP + gRPC transports.
  """
  use ExUnit.Case, async: false

  alias LangOS.{Benchmark, MCP, ReferenceMarker, Splitter, VocabPlugin}

  describe "splitter" do
    test "splits sentences with spans into the source text" do
      text = "Register Clarissa. She starts Monday. Thank you!"
      units = Splitter.split(text)

      assert length(units) == 3
      assert Enum.map(units, & &1["text"]) ==
               ["Register Clarissa.", "She starts Monday.", "Thank you!"]

      [first | _] = units
      [start, stop] = first["span"]
      assert binary_part(text, start, stop - start) =~ "Register Clarissa."
    end

    test "abbreviations and decimals do not end a unit" do
      units = Splitter.split("Dr. Uwera teaches Biology A1. The fee is 2.5 dollars.")
      assert length(units) == 2
      assert hd(units)["text"] == "Dr. Uwera teaches Biology A1."
    end
  end

  describe "document understanding" do
    test "parses units in parallel and marks coreference candidates" do
      assert {:ok, resp} =
               LangOS.understand_document(%{
                 "text" => "Register Clarissa in Biology A1. Do you know her?",
                 "locale" => "en"
               })

      assert resp["unit_count"] == 2
      [unit1, unit2] = resp["units"]

      assert unit1["ir"]["utterance_type"] == "command"

      # Unit 2's "her" is a discourse reference with candidates from unit 1.
      previous_entity =
        Enum.find(unit2["ir"]["references"], &(&1["slot"] == "previous_entity"))

      assert previous_entity != nil
      assert previous_entity["resolution"] == "deferred"

      candidates = Enum.map(previous_entity["candidates"] || [], & &1["canonical"])
      assert "clarissa" in candidates
    end

    test "single-utterance understand also carries reference slots" do
      assert {:ok, resp} = LangOS.understand(%{"text" => "I love you.", "locale" => "en"})

      slots = Enum.map(resp["ir"]["references"], & &1["slot"])
      assert "speaker" in slots
      assert "listener" in slots
    end
  end

  describe "vocabulary plugins" do
    test "education-vocab is installed and contributes kind hints" do
      VocabPlugin.reload()
      assert Enum.any?(VocabPlugin.installed(), &(&1["id"] == "education-vocab"))

      assert VocabPlugin.kind_hint("homework") == "assignment"
      assert VocabPlugin.kind_hint("Biology A1") == "course"
      assert VocabPlugin.kind_hint("A1") == "identifier"
      assert VocabPlugin.kind_hint("the weather") == nil
    end

    test "syntax engine types concepts with plugin hints" do
      assert {:ok, resp} =
               LangOS.understand(%{"text" => "Can I join the class?", "locale" => "en"})

      class_node =
        Enum.find(resp["ir"]["graph"]["nodes"], fn n ->
          get_in(n, ["concept", "canonical"]) == "class"
        end)

      # "class" -> course via education-vocab priors
      assert get_in(class_node, ["concept", "kind"]) == "course"
    end
  end

  describe "per-stage routing" do
    test "parse chain is configurable via routing.stages.parse" do
      chain = LangOS.Router.parse_chain(%{})

      assert LangOS.Engine.Rule in chain
      assert LangOS.Engine.Syntax in chain
      assert Enum.find_index(chain, &(&1 == LangOS.Engine.Rule)) <
               Enum.find_index(chain, &(&1 == LangOS.Engine.Syntax))
    end
  end

  describe "benchmark harness" do
    test "runs the corpus and reports accuracy + latency" do
      assert {:ok, report} = Benchmark.run("bench/corpus.jsonl")

      assert report["total"] >= 20
      assert report["accuracy"] == 100.0
      assert report["latency"]["p50_ms"] > 0
      assert is_list(report["failures"])
    end
  end

  describe "MCP transport" do
    test "initialize / tools list / tool call over JSON-RPC" do
      assert {:reply, init} =
               MCP.Server.handle_message(%{"jsonrpc" => "2.0", "id" => 1, "method" => "initialize"})

      assert init["result"]["serverInfo"]["name"] == "langos"

      assert {:reply, list} =
               MCP.Server.handle_message(%{"jsonrpc" => "2.0", "id" => 2, "method" => "tools/list"})

      names = Enum.map(list["result"]["tools"], & &1["name"])
      assert "langos_understand" in names
      assert "langos_translate" in names

      assert {:reply, call} =
               MCP.Server.handle_message(%{
                 "jsonrpc" => "2.0",
                 "id" => 3,
                 "method" => "tools/call",
                 "params" => %{
                   "name" => "langos_understand",
                   "arguments" => %{"text" => "Can I join the class?"}
                 }
               })

      assert call["result"]["isError"] == false
      [%{"text" => payload}] = call["result"]["content"]
      ir = Jason.decode!(payload)["ir"]
      assert ir["utterance_type"] == "question"

      assert :noreply =
               MCP.Server.handle_message(%{"jsonrpc" => "2.0", "method" => "notifications/initialized"})
    end
  end

  describe "gRPC transport" do
    test "understand roundtrip over port 9474" do
      case DynamicSupervisor.start_link(strategy: :one_for_one, name: GRPC.Client.Supervisor) do
        {:ok, _} -> :ok
        {:error, {:already_started, _}} -> :ok
      end

      port = LangOS.Config.get(["server", "grpc", "port"], 9474)
      assert {:ok, channel} = GRPC.Stub.connect("127.0.0.1:#{port}")

      request = %Langos.V1.UnderstandRequest{text: "Is the world green?", locale: ""}
      assert {:ok, reply} = Langos.V1.LangOS.Stub.understand(channel, request)

      ir = Jason.decode!(reply.ir_json)
      pred = Enum.find(ir["graph"]["nodes"], &(&1["type"] == "predicate"))
      assert pred["predicate"]["id"] == "STA_000001"
      assert ir["utterance_type"] == "question"
    end
  end

  describe "translate via IR pivot" do
    test "fills the ir_summary template instead of leaking the placeholder" do
      assert {:ok, resp} =
               LangOS.translate(%{
                 "text" => "Register Clarissa in Biology A1.",
                 "from" => "en",
                 "to" => "fr"
               })

      refute resp["text"] =~ "{{"
      assert resp["text"] =~ "ACTION_REGISTER"
    end
  end

  describe "reference marker unit" do
    test "named_entities extracts non-literal concepts" do
      {:ok, resp} = LangOS.understand(%{"text" => "Register Clarissa in Biology A1.", "locale" => "en"})
      entities = ReferenceMarker.named_entities(resp["ir"], 0)

      canonicals = Enum.map(entities, & &1["canonical"])
      assert "clarissa" in canonicals
    end
  end
end
