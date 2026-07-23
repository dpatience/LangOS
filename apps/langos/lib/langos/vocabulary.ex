defmodule LangOS.Vocabulary do
  @moduledoc """
  The Semantic Vocabulary — the kernel's system call table.

  Loads schemas/semantic_vocabulary.json once into `:persistent_term` and
  serves O(1) lookups. The Semantic Mapper uses `roles/1` to assign
  subject/object arguments to the roles each predicate actually defines
  (EVENT_JOIN -> [patient, container, time], STATE_LOVE ->
  [experiencer, stimulus], ...).
  """

  @key :langos_vocabulary

  @spec entry(String.t()) :: map() | nil
  def entry(vocab_id) when is_binary(vocab_id) do
    Map.get(table(), vocab_id)
  end

  @doc "Ordered semantic roles the predicate defines. Empty list if unknown."
  @spec roles(String.t()) :: [String.t()]
  def roles(vocab_id) do
    case entry(vocab_id) do
      %{"roles" => roles} when is_list(roles) -> roles
      _ -> []
    end
  end

  @spec category(String.t()) :: String.t() | nil
  def category(vocab_id) do
    case entry(vocab_id) do
      %{"category" => cat} -> cat
      _ -> nil
    end
  end

  @doc "Lookup a vocabulary entry by its semantic symbol."
  @spec by_symbol(String.t()) :: map() | nil
  def by_symbol(symbol) when is_binary(symbol) do
    case :persistent_term.get(:langos_vocab_by_symbol, nil) do
      nil ->
        index = build_symbol_index()
        :persistent_term.put(:langos_vocab_by_symbol, index)
        Map.get(index, symbol)

      index ->
        Map.get(index, symbol)
    end
  end

  defp build_symbol_index do
    Map.new(table(), fn {_id, entry} -> {entry["symbol"], entry} end)
  end

  @spec size() :: non_neg_integer()
  def size, do: map_size(table())

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
    with path when is_binary(path) <- resolve_path("schemas/semantic_vocabulary.json"),
         {:ok, body} <- File.read(path),
         {:ok, %{"vocabulary" => items}} <- Jason.decode(body) do
      Map.new(items, fn item -> {item["id"], item} end)
    else
      _ -> %{}
    end
  end

  defp resolve_path(relative) do
    candidates = [
      Path.expand(relative, File.cwd!()),
      Path.expand(Path.join("../../../..", relative), __DIR__)
    ]

    Enum.find(candidates, &File.exists?/1)
  end
end
