defmodule LangOS.API.Router do
  @moduledoc """
  Plug router for LangOS native HTTP API.
  """
  use Plug.Router
  use Plug.ErrorHandler

  plug Plug.Logger
  plug :match
  plug Plug.Parsers, parsers: [:json], json_decoder: Jason
  plug :dispatch

  get "/v1/health" do
    uptime = LangOS.API.Health.uptime_seconds()

    json(conn, 200, %{
      status: "ok",
      version: "0.1.0",
      uptime_seconds: uptime
    })
  end

  get "/v1/languages" do
    languages = LangOS.LanguagePack.Registry.list()
    json(conn, 200, %{languages: languages})
  end

  get "/v1/engines" do
    engines = LangOS.Engine.Registry.list()
    json(conn, 200, %{engines: engines})
  end

  post "/v1/understand" do
    handle(conn, fn -> LangOS.understand(conn.body_params) end)
  end

  post "/v1/understand/document" do
    handle(conn, fn -> LangOS.understand_document(conn.body_params) end)
  end

  # Server-sent events: one `unit` event per parsed semantic unit, in order,
  # followed by a `done` event with the document summary. First unit arrives
  # while the rest of the document is still parsing.
  post "/v1/understand/stream" do
    conn =
      conn
      |> put_resp_content_type("text/event-stream")
      |> put_resp_header("cache-control", "no-cache")
      |> send_chunked(200)

    result =
      LangOS.Pipeline.understand_document(conn.body_params, fn unit ->
        {:ok, _} = chunk(conn, "event: unit\ndata: #{Jason.encode!(unit)}\n\n")
      end)

    case result do
      {:ok, summary} ->
        done = Map.drop(summary, ["units"])
        {:ok, conn} = chunk(conn, "event: done\ndata: #{Jason.encode!(done)}\n\n")
        conn

      {:error, reason} ->
        {:ok, conn} = chunk(conn, "event: error\ndata: #{Jason.encode!(%{error: inspect(reason)})}\n\n")
        conn
    end
  end

  post "/v1/express" do
    handle(conn, fn -> LangOS.express(conn.body_params) end)
  end

  post "/v1/translate" do
    handle(conn, fn -> LangOS.translate(conn.body_params) end)
  end

  # OpenAI-compatible endpoint: point an OpenAI client's base URL at LangOS.
  post "/v1/chat/completions" do
    handle(conn, fn -> LangOS.API.Compat.chat_completions(conn.body_params) end)
  end

  # Anthropic-compatible endpoint.
  post "/v1/messages" do
    handle(conn, fn -> LangOS.API.Compat.messages(conn.body_params) end)
  end

  match _ do
    json(conn, 404, %{error: "not_found"})
  end

  defp handle(conn, fun) do
    case fun.() do
      {:ok, body} ->
        json(conn, 200, body)

      {:error, :missing_text} ->
        json(conn, 400, %{error: "missing_text"})

      {:error, :missing_template_or_ir} ->
        json(conn, 400, %{error: "missing_template_or_ir"})

      {:error, {:invalid_ir, errors}} ->
        json(conn, 422, %{error: "invalid_ir", details: errors})

      {:error, reason} ->
        json(conn, 400, %{error: inspect(reason)})
    end
  end

  defp json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end
