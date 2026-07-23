defmodule LangOSLexiconTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias LangOS.Lexicon

  test "lexicon has thousands of entries" do
    assert Lexicon.entry_count("en") > 5000
  end

  test "O(1) lookup: base form" do
    entry = Lexicon.lookup("register")
    assert entry["id"] == "ACT_000005"
    assert entry["symbol"] == "ACTION_REGISTER"
  end

  test "lookup resolves inflected forms" do
    assert Lexicon.lookup("registered")["id"] == "ACT_000005"
    assert Lexicon.lookup("registering")["id"] == "ACT_000005"
    assert Lexicon.lookup("knew")["id"] == "STA_000003"
    assert Lexicon.lookup("known")["id"] == "STA_000003"
  end

  test "lookup resolves synonyms to the same vocabulary ID" do
    assert Lexicon.lookup("enroll")["id"] == "ACT_000005"
    assert Lexicon.lookup("register")["id"] == Lexicon.lookup("enroll")["id"]
  end

  test "pronouns resolve to reserved references" do
    assert Lexicon.lookup("me")["ref"] == "REF_SPEAKER"
    assert Lexicon.lookup("you")["ref"] == "REF_LISTENER"
    assert Lexicon.lookup("she")["ref"] == "REF_PREVIOUS_ENTITY"
    assert Lexicon.lookup("tomorrow")["ref"] == "REF_TIME_FUTURE"
  end

  test "annotate: longest phrase wins over its prefix" do
    matches = Lexicon.annotate("please sign up alice")
    surfaces = Enum.map(matches, & &1["surface"])
    assert "sign up" in surfaces
  end

  test "annotate_words finds pronouns inside phrases, with correct spans" do
    matches = Lexicon.annotate_words("Do you know me?")

    you = Enum.find(matches, &(&1["surface"] == "you"))
    me = Enum.find(matches, &(&1["surface"] == "me"))

    assert you["span"] == [3, 6]
    assert you["entry"]["ref"] == "REF_LISTENER"
    assert me["span"] == [12, 14]
    assert me["entry"]["ref"] == "REF_SPEAKER"
  end

  test "unknown words return nil" do
    assert Lexicon.lookup("xyzzyplugh") == nil
  end
end
