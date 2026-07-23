defmodule LangOS.SDK do
  @moduledoc """
  Elixir client for the LangOS HTTP API.

  ## Examples

      LangOS.SDK.understand(%{"text" => "Register Clarissa in Biology A1."})
      LangOS.SDK.express(%{"template" => "missing_fields", "locale" => "en", "data" => %{"entity" => "Clarissa", "fields" => "age"}})
  """

  @default_base "http://127.0.0.1:9473"

  def understand(request, opts \\ []), do: post("/v1/understand", request, opts)
  def express(request, opts \\ []), do: post("/v1/express", request, opts)
  def translate(request, opts \\ []), do: post("/v1/translate", request, opts)
  def health(opts \\ []), do: get("/v1/health", opts)

  defp post(path, body, opts) do
    request(:post, path, Jason.encode!(body), opts)
  end

  defp get(path, opts) do
    request(:get, path, nil, opts)
  end

  defp request(method, path, body, opts) do
    base = Keyword.get(opts, :base_url, @default_base)
    url = base <> path
    headers = [{~c"content-type", ~c"application/json"}]

    http_opts = [body_format: :binary]
    http_request = format_request(method, url, headers, body)

    case :httpc.request(method, http_request, http_opts, []) do
      {:ok, {{_, 200, _}, _response_headers, response_body}} ->
        {:ok, Jason.decode!(response_body)}

      {:ok, {{_, status, _}, _, response_body}} ->
        {:error, {status, Jason.decode!(response_body)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp format_request(:get, url, headers, _body) do
    {~c"GET", {String.to_charlist(url), headers}}
  end

  defp format_request(:post, url, headers, body) do
    {~c"POST", {String.to_charlist(url), headers, ~c"application/json", body}}
  end
end
