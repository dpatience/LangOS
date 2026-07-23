defmodule LangOS.VocabPlugin do
  @moduledoc """
  Vocabulary plugins — domain hints without domain logic.

  A plugin (`plugins/<id>/vocab.json`) contributes:

  - **terms**: exact surface phrases mapped to a concept kind
    ("homework" -> assignment)
  - **entity_hints**: regex patterns for entity shapes
    ("A1" -> identifier, "Biology A1" -> course)
  - **priors**: disambiguation defaults for ambiguous nouns
    ("class" -> course in an education deployment)

  Plugins never define intents, business rules, or actions. The Syntax
  engine consults `kind_hint/1` when typing concept nodes, so the same
  sentence produces richer concept kinds when a domain plugin is installed —
  and identical structure when it is not.

  Installed plugins come from config `plugins.installed`; all are merged in
  order (later plugins win on conflicts) and served from `:persistent_term`.
  """

  alias LangOS.Config

  @key :langos_vocab_plugins

  @doc "Concept kind hint for a surface phrase, or nil when no plugin knows it."
  @spec kind_hint(String.t()) :: String.t() | nil
  def kind_hint(surface) when is_binary(surface) do
    %{terms: terms, hints: hints, priors: priors} = table()
    normalized = surface |> String.trim() |> String.downcase()

    cond do
      kind = get_in(terms, [normalized, "kind"]) -> kind
      kind = Map.get(priors, normalized) -> kind
      kind = hint_match(hints, String.trim(surface)) -> kind
      true -> nil
    end
  end

  @spec installed() :: [map()]
  def installed, do: table().manifests

  @doc "Reload plugins from disk (used after install/config change and in tests)."
  @spec reload() :: :ok
  def reload do
    :persistent_term.put(@key, load())
    :ok
  end

  defp hint_match(hints, surface) do
    Enum.find_value(hints, fn {regex, kind} ->
      if Regex.match?(regex, surface), do: kind
    end)
  end

  defp table do
    case :persistent_term.get(@key, nil) do
      nil ->
        loaded = load()
        :persistent_term.put(@key, loaded)
        loaded

      loaded ->
        loaded
    end
  end

  defp load do
    empty = %{terms: %{}, hints: [], priors: %{}, manifests: []}

    installed_ids()
    |> Enum.map(&read_plugin/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.reduce(empty, fn plugin, acc ->
      hints =
        plugin
        |> Map.get("entity_hints", [])
        |> Enum.flat_map(fn hint ->
          case Regex.compile(hint["pattern"], "iu") do
            {:ok, regex} -> [{regex, hint["kind"]}]
            _ -> []
          end
        end)

      manifest = %{
        "id" => plugin["id"],
        "name" => plugin["name"],
        "version" => plugin["version"],
        "domain" => plugin["domain"]
      }

      %{
        terms: Map.merge(acc.terms, downcase_keys(Map.get(plugin, "terms", %{}))),
        hints: acc.hints ++ hints,
        priors: Map.merge(acc.priors, downcase_keys(Map.get(plugin, "priors", %{}))),
        manifests: acc.manifests ++ [manifest]
      }
    end)
  end

  defp read_plugin(id) do
    path = Path.join([plugins_dir(), id, "vocab.json"])

    with {:ok, body} <- File.read(path),
         {:ok, plugin} <- Jason.decode(body) do
      plugin
    else
      _ -> nil
    end
  end

  defp installed_ids do
    case Process.whereis(Config) do
      nil -> []
      _ -> Config.get(["plugins", "installed"], [])
    end
  end

  defp plugins_dir do
    dir =
      case Process.whereis(Config) do
        nil -> "plugins"
        _ -> Config.get(["plugins", "dir"], "plugins")
      end

    candidates = [
      Path.expand(dir, File.cwd!()),
      Path.expand(Path.join("../../../..", dir), __DIR__)
    ]

    Enum.find(candidates, dir, &File.exists?/1)
  end

  defp downcase_keys(map) do
    Map.new(map, fn {k, v} -> {String.downcase(k), v} end)
  end
end
