defmodule LangOSStatEngineTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias LangOS.{Engine.Stat, Model}

  test "trained model is loaded" do
    model = Model.intent("en")
    assert model["algorithm"] == "multinomial_naive_bayes"
    assert model["class_count"] > 300
  end

  test "classifies free-form utterances the rule engine cannot parse" do
    model = Model.intent("en")

    assert {"STA_000026", "STATE_LOVE", _} = Stat.classify("i love you", model)
    assert {"META_000003", "META_THANK", _} = Stat.classify("thank you so much", model)
    assert {"QRY_000001", "QUERY_KNOW", _} = Stat.classify("do you know me", model)
    assert {"ACT_000089", "ACTION_SUMMARIZE", _} = Stat.classify("please summarize the report", model)
  end

  test "understand pipeline routes free-form text through the stat engine" do
    assert {:ok, resp} = LangOS.understand(%{"text" => "I love you.", "locale" => "en"})
    ir = resp["ir"]

    pred = Enum.find(ir["graph"]["nodes"], &(&1["type"] == "predicate"))
    assert pred["predicate"]["id"] == "STA_000026"
    assert pred["predicate"]["symbol"] == "STATE_LOVE"
    assert ir["utterance_type"] == "statement"
    assert ir["meta"]["engine"]["parser"] == "stat_naive_bayes"

    refs =
      ir["graph"]["nodes"]
      |> Enum.filter(&(&1["type"] == "reference"))
      |> Enum.map(&get_in(&1, ["reference", "ref"]))

    assert "REF_SPEAKER" in refs
    assert "REF_LISTENER" in refs
  end

  test "stat extracts pronoun references with spans as mentions" do
    assert {:ok, resp} = LangOS.understand(%{"text" => "I miss my family.", "locale" => "en"})
    ir = resp["ir"]

    pred = Enum.find(ir["graph"]["nodes"], &(&1["type"] == "predicate"))
    assert pred["predicate"]["id"] == "STA_000029"

    i_mention = Enum.find(ir["mentions"], &(&1["surface"] == "I"))
    assert i_mention != nil
    assert i_mention["span"] == [0, 1]
  end
end
