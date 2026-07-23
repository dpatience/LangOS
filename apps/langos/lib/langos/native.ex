defmodule LangOS.Native do
  @moduledoc """
  Rustler NIF bindings to LangOS Rust core.
  Falls back to pure Elixir when NIFs are unavailable.
  """
  use Rustler, otp_app: :langos, crate: "langos_nif", path: "../../crates/langos_nif"

  def tokenize(_text), do: :erlang.nif_error(:nif_not_loaded)
  def count_tokens(_text), do: :erlang.nif_error(:nif_not_loaded)
  def parse_patterns(_text, _rules_json), do: :erlang.nif_error(:nif_not_loaded)
  def build_ir(_lang, _text, _vid, _sym, _utype, _args, _conf, _engine), do: :erlang.nif_error(:nif_not_loaded)
  def detect_language(_text, _locale), do: :erlang.nif_error(:nif_not_loaded)

  @spec safe_tokenize(String.t()) :: {:ok, list()} | {:error, term()}
  def safe_tokenize(text) do
    with json when is_binary(json) <- tokenize(text),
         {:ok, tokens} <- Jason.decode(json) do
      {:ok, tokens}
    else
      _ -> fallback_tokenize(text)
    end
  rescue
    _ -> fallback_tokenize(text)
  end

  @spec safe_count_tokens(String.t()) :: non_neg_integer()
  def safe_count_tokens(text) do
    count_tokens(text)
  rescue
    _ -> text |> String.split(~r/\s+/, trim: true) |> length()
  end

  @spec safe_parse_patterns(String.t(), String.t()) :: {:ok, map() | nil}
  def safe_parse_patterns(text, rules_json) do
    case parse_patterns(text, rules_json) do
      "null" -> {:ok, nil}
      json when is_binary(json) ->
        case Jason.decode(json) do
          {:ok, nil} -> {:ok, nil}
          {:ok, map} when is_map(map) -> {:ok, map}
          _ -> {:ok, nil}
        end
    end
  rescue
    _ -> LangOS.Parser.Pattern.match(text, rules_json)
  end

  @spec safe_build_ir(keyword()) :: {:ok, map()} | {:error, term()}
  def safe_build_ir(opts) do
    language = Keyword.fetch!(opts, :language)
    text = Keyword.fetch!(opts, :text)
    vocab_id = Keyword.fetch!(opts, :vocab_id)
    symbol = Keyword.fetch!(opts, :symbol)
    unit_type = Keyword.get(opts, :unit_type, "command")
    arguments = Keyword.fetch!(opts, :arguments)
    confidence = Keyword.get(opts, :confidence, %{"overall" => 0.9, "predicate" => 0.9, "roles" => 0.9, "references" => 1.0})
    engine = Keyword.get(opts, :engine, %{"parser" => "unknown"})

    args_json = Jason.encode!(arguments)
    conf_json = Jason.encode!(confidence)
    engine_json = Jason.encode!(engine)

    with json when is_binary(json) <-
           build_ir(language, text, vocab_id, symbol, unit_type, args_json, conf_json, engine_json),
         {:ok, ir} <- Jason.decode(json) do
      {:ok, ir}
    else
      _ -> {:error, :nif_build_failed}
    end
  rescue
    _ -> {:error, :nif_not_loaded}
  end

  @spec safe_detect_language(String.t(), String.t() | nil) :: String.t()
  def safe_detect_language(text, locale_hint \\ nil) do
    detect_language(text, locale_hint)
  rescue
    _ -> locale_hint || "en"
  end

  defp fallback_tokenize(text) do
    tokens =
      Regex.scan(~r/[A-Za-z0-9']+|[^\sA-Za-z0-9]/, text)
      |> Enum.with_index()
      |> Enum.flat_map(fn
        [{token, start}, _] ->
          [%{"text" => token, "start" => start, "end" => start + String.length(token), "kind" => "word"}]
        _ -> []
      end)
    {:ok, tokens}
  end
end
