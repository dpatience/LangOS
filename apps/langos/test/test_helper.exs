ExUnit.start()

Application.put_env(:langos, :cache_enabled, false)

case Application.ensure_all_started(:langos) do
  {:ok, _} -> :ok
  {:error, {:already_started, :langos}} -> :ok
  {:error, reason} -> raise "failed to start langos: #{inspect(reason)}"
end
