defmodule LangOSPackMorphologyTest do
  @moduledoc """
  Turkish (suffix-agglutinative, SOV) and expanded Kinyarwanda
  (prefix-agglutinative, SVO) through the pack-driven syntax path.
  """
  use ExUnit.Case, async: false

  alias LangOS.LanguageDetector

  defp understand!(text, locale) do
    request = if locale, do: %{"text" => text, "locale" => locale}, else: %{"text" => text}
    assert {:ok, resp} = LangOS.understand(request)
    resp
  end

  defp predicate(resp) do
    Enum.find(resp["ir"]["graph"]["nodes"], &(&1["type"] == "predicate"))["predicate"]
  end

  defp reference_refs(resp) do
    resp["ir"]["graph"]["nodes"]
    |> Enum.filter(&(&1["type"] == "reference"))
    |> Enum.map(& &1["reference"]["ref"])
  end

  describe "Turkish detection" do
    test "Turkish is detected without a locale hint" do
      assert LanguageDetector.detect("Seni seviyorum.") == "tr"
      assert LanguageDetector.detect("Yemek istiyorum.") == "tr"
      assert LanguageDetector.detect("Fotosentez nedir?") == "tr"
    end

    test "Turkish does not steal English or Kinyarwanda" do
      assert LanguageDetector.detect("Register Clarissa in Biology A1.") == "en"
      assert LanguageDetector.detect("Ndashaka kurya") == "rw"
    end
  end

  describe "Turkish SOV parsing with suffix morphology" do
    test "'Yemek istiyorum.' — clause-final verb, subject from -iyorum suffix" do
      resp = understand!("Yemek istiyorum.", "tr")

      assert predicate(resp)["symbol"] == "STATE_WANT"
      assert resp["ir"]["utterance_type"] == "statement"
      assert "REF_SPEAKER" in reference_refs(resp)

      # The object precedes the verb in SOV order.
      concept =
        Enum.find(resp["ir"]["graph"]["nodes"], &(&1["type"] == "concept"))

      assert concept["concept"]["canonical"] == "yemek"
    end

    test "'Seni seviyorum.' — case-marked pronoun is the object, not the subject" do
      resp = understand!("Seni seviyorum.", "tr")

      assert predicate(resp)["symbol"] == "STATE_LOVE"
      refs = reference_refs(resp)
      assert "REF_SPEAKER" in refs
      assert "REF_LISTENER" in refs
    end

    test "'Clarissa'yı Biyoloji A1'e kaydet.' — apostrophe case suffixes stripped from canonicals" do
      resp = understand!("Clarissa'yı Biyoloji A1'e kaydet.", "tr")

      assert predicate(resp)["symbol"] == "ACTION_REGISTER"
      assert resp["ir"]["utterance_type"] == "command"
    end

    test "verb-final imperative without subject is a command" do
      resp = understand!("Kitabı oku.", "tr")

      assert predicate(resp)["symbol"] == "ACTION_READ"
      assert resp["ir"]["utterance_type"] == "command"
    end

    test "'Fotosentez nedir?' -> QUESTION + ACTION_DEFINE" do
      resp = understand!("Fotosentez nedir?", "tr")

      assert predicate(resp)["id"] == "ACT_000221"
      assert resp["ir"]["utterance_type"] == "question"
    end
  end

  describe "expanded Kinyarwanda" do
    test "'Ndagukunda.' — nda- subject prefix resolves to REF_SPEAKER" do
      resp = understand!("Ndagukunda.", "rw")

      assert predicate(resp)["symbol"] == "STATE_LOVE"
      assert "REF_SPEAKER" in reference_refs(resp)
      assert resp["ir"]["utterance_type"] == "statement"
    end

    test "'Ndashaka kurya.' still parses (want + eat object)" do
      resp = understand!("Ndashaka kurya.", "rw")

      assert predicate(resp)["symbol"] == "STATE_WANT"
      assert "REF_SPEAKER" in reference_refs(resp)
    end

    test "'Arasinzira.' — third-person prefix on an expanded verb" do
      resp = understand!("Arasinzira.", "rw")

      assert predicate(resp)["symbol"] == "ACTION_SLEEP"
      assert "REF_PREVIOUS_ENTITY" in reference_refs(resp)
    end

    test "'Fotosentezi ni iki?' -> QUESTION + ACTION_DEFINE via pattern" do
      resp = understand!("Fotosentezi ni iki?", "rw")

      assert predicate(resp)["id"] == "ACT_000221"
      assert resp["ir"]["utterance_type"] == "question"
    end

    test "'Numva inzara.' — n- prefix + expanded verb kumva" do
      resp = understand!("Numva inzara.", "rw")

      assert predicate(resp)["symbol"] == "ACTION_HEAR"
      assert "REF_SPEAKER" in reference_refs(resp)
    end

    test "greetings and meta acts map to META primitives" do
      assert predicate(understand!("Murakoze cyane.", "rw"))["symbol"] == "META_THANK"
      assert predicate(understand!("Muraho!", "rw"))["symbol"] == "META_GREET"
    end
  end

  describe "express in new packs" do
    test "Turkish express templates render" do
      assert {:ok, resp} =
               LangOS.express(%{"template" => "success", "locale" => "tr", "data" => %{}})

      assert resp["text"] == "Tamamlandı."
    end

    test "Kinyarwanda greeting template renders" do
      assert {:ok, resp} =
               LangOS.express(%{"template" => "greeting", "locale" => "rw", "data" => %{}})

      assert resp["text"] == "Muraho!"
    end
  end
end
