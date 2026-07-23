defmodule LangOSSyntaxEngineTest do
  @moduledoc """
  The deterministic understanding pipeline: structure first, meaning second.

  These are the four failure cases from the Phase 2 review, plus structural
  coverage: question forms map to semantic actions with their real objects,
  subjects/objects become role edges, and language detection routes each
  utterance to the pack that actually speaks the language.
  """
  use ExUnit.Case, async: false

  alias LangOS.{Engine.Syntax, LanguageDetector}

  defp understand!(text, opts \\ %{}) do
    assert {:ok, resp} = LangOS.understand(Map.merge(%{"text" => text}, opts))
    resp
  end

  defp predicate(ir), do: Enum.find(ir["graph"]["nodes"], &(&1["type"] == "predicate"))

  defp role_targets(ir) do
    nodes = Map.new(ir["graph"]["nodes"], &{&1["id"], &1})

    Map.new(ir["graph"]["edges"], fn edge ->
      node = nodes[edge["to"]]
      value = get_in(node, ["reference", "ref"]) || get_in(node, ["concept", "canonical"])
      {edge["role"], value}
    end)
  end

  describe "review example 1 — question forms map to semantic actions" do
    test "'What is the meaning of photosynthesis?' -> QUESTION + ACTION_DEFINE(photosynthesis)" do
      ir = understand!("What is the meaning of photosynthesis?")["ir"]

      assert ir["utterance_type"] == "question"
      assert predicate(ir)["predicate"]["id"] == "ACT_000221"
      assert predicate(ir)["predicate"]["symbol"] == "ACTION_DEFINE"
      assert role_targets(ir)["theme"] == "photosynthesis"
    end

    test "'What is photosynthesis?' -> same graph: the linguistic form differs, the meaning does not" do
      ir = understand!("What is photosynthesis?")["ir"]

      assert ir["utterance_type"] == "question"
      assert predicate(ir)["predicate"]["symbol"] == "ACTION_DEFINE"
      assert role_targets(ir)["theme"] == "photosynthesis"
    end
  end

  describe "review example 2 — no argument is dropped" do
    test "'Can I join the class?' -> QUESTION + EVENT_JOIN(REF_SPEAKER, class)" do
      ir = understand!("Can I join the class?")["ir"]

      assert ir["utterance_type"] == "question"
      assert predicate(ir)["predicate"]["id"] == "EVT_000001"

      targets = role_targets(ir)
      assert targets["patient"] == "REF_SPEAKER"
      assert targets["container"] == "class"
    end
  end

  describe "review example 3 — syntax, not word counting" do
    test "'Is the world green?' -> QUESTION + STATE_BE(theme world, attribute green)" do
      ir = understand!("Is the world green?")["ir"]

      assert ir["utterance_type"] == "question"
      assert predicate(ir)["predicate"]["id"] == "STA_000001"

      targets = role_targets(ir)
      assert targets["theme"] == "world"
      assert targets["attribute"] == "green"
    end
  end

  describe "review example 4 — language detection routes to the right pack" do
    test "Kinyarwanda is detected and parsed by the Kinyarwanda pack" do
      assert LanguageDetector.detect("Nshaka kurya", nil) == "rw"
      assert LanguageDetector.detect("ibiryo ni iki?", nil) == "rw"

      resp = understand!("Nshaka kurya")
      assert resp["language"] == "rw"

      # Morphology: nshaka = n- (REF_SPEAKER) + shaka (STATE_WANT)
      ir = resp["ir"]
      assert predicate(ir)["predicate"]["id"] == "STA_000004"
      assert role_targets(ir)["experiencer"] == "REF_SPEAKER"
    end

    test "French is detected without a locale hint" do
      assert LanguageDetector.detect("Je veux manger", nil) == "fr"
      assert understand!("Je veux manger")["language"] == "fr"
    end

    test "English still wins for English text" do
      assert LanguageDetector.detect("Register Clarissa in Biology A1.", nil) == "en"
    end

    test "explicit locale hint is respected" do
      assert LanguageDetector.detect("anything at all", "fr-FR") == "fr"
    end
  end

  describe "structural clause parsing" do
    test "subject and object become role edges from vocabulary role metadata" do
      ir = understand!("Do you know me?")["ir"]

      assert ir["utterance_type"] == "question"
      assert predicate(ir)["predicate"]["id"] == "STA_000003"

      targets = role_targets(ir)
      assert targets["experiencer"] == "REF_LISTENER"
      assert targets["theme"] == "REF_SPEAKER"
    end

    test "statement clause: 'I love you' -> STATE_LOVE(experiencer, stimulus)" do
      assert {:ok, tree} = Syntax.parse("I love you", locale: "en")

      assert tree["vocab_id"] == "STA_000026"
      assert tree["unit_type"] == "statement"

      roles = Map.new(tree["arguments"], &{&1["role"], &1["ref"] || &1["label"]})
      assert roles["experiencer"] == "REF_SPEAKER"
      assert roles["stimulus"] == "REF_LISTENER"
    end

    test "imperative with prepositional attachment" do
      assert {:ok, tree} = Syntax.parse("Enroll Clarissa in Biology A1", locale: "en")

      assert tree["vocab_id"] == "ACT_000005"
      assert tree["unit_type"] == "command"

      roles = Map.new(tree["arguments"], &{&1["role"], &1["label"]})
      assert roles["patient"] == "Clarissa"
      assert roles["container"] == "Biology A1"
    end

    test "wh-copula keeps the question focus" do
      assert {:ok, tree} = Syntax.parse("Where is Alice?", locale: "en")

      assert tree["vocab_id"] == "STA_000001"
      assert tree["unit_type"] == "question"

      focus = Enum.find(tree["arguments"], &(&1["role"] == "focus"))
      assert focus["canonical"] == "location"

      theme = Enum.find(tree["arguments"], &(&1["role"] == "theme"))
      assert theme["label"] == "Alice"
      assert theme["kind"] == "named"
    end

    test "copula statement: 'The sky is blue.'" do
      assert {:ok, tree} = Syntax.parse("The sky is blue.", locale: "en")

      assert tree["vocab_id"] == "STA_000001"
      assert tree["unit_type"] == "statement"
    end

    test "no verb structure -> no parse, defers to fallback engines" do
      assert {:error, :no_parse} = Syntax.parse("thank you so much", locale: "en")
      assert {:error, :no_parse} = Syntax.parse("wow amazing stuff", locale: "en")
    end
  end
end
