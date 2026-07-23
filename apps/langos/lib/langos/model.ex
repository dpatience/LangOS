defmodule LangOS.Model do
  @moduledoc """
  Loads trained LangOS models (produced by python/langos_train) into
  `:persistent_term` for lock-free access.
  """

  @spec intent(String.t()) :: map() | nil
  def intent(locale \\ "en") do
    key = {:langos_model_intent, locale}

    case :persistent_term.get(key, :missing) do
      :missing ->
        model = load(locale)
        :persistent_term.put(key, model)
        model

      model ->
        model
    end
  end

  defp load(locale) do
    path = resolve_path(Path.join(["models", locale, "intent.json"]))

    with true <- is_binary(path),
         {:ok, body} <- File.read(path),
         {:ok, model} <- Jason.decode(body) do
      model
    else
      _ -> nil
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
