defmodule LangOS.GRPC.Server do
  @moduledoc """
  gRPC transport (default port 9474) — a thin adapter over the same core
  runtime as the HTTP API. Enable via config:

      "server": {"grpc": {"enabled": true, "port": 9474}}
  """
  use GRPC.Server, service: Langos.V1.LangOS.Service

  @spec understand(Langos.V1.UnderstandRequest.t(), GRPC.Server.Stream.t()) ::
          Langos.V1.IRReply.t()
  def understand(request, _stream) do
    payload = %{"text" => request.text}
    payload = if request.locale == "", do: payload, else: Map.put(payload, "locale", request.locale)

    case LangOS.understand(payload) do
      {:ok, resp} ->
        %Langos.V1.IRReply{
          ir_json: Jason.encode!(resp["ir"]),
          language: resp["language"] || "",
          latency_ms: resp["latency_ms"] || 0
        }

      {:error, reason} ->
        raise GRPC.RPCError, status: :invalid_argument, message: inspect(reason)
    end
  end

  @spec express(Langos.V1.ExpressRequest.t(), GRPC.Server.Stream.t()) ::
          Langos.V1.TextReply.t()
  def express(request, _stream) do
    data =
      case Jason.decode(request.data_json) do
        {:ok, map} when is_map(map) -> map
        _ -> %{}
      end

    payload = %{"template" => request.template, "locale" => request.locale, "data" => data}

    case LangOS.express(payload) do
      {:ok, resp} ->
        %Langos.V1.TextReply{text: resp["text"] || "", latency_ms: resp["latency_ms"] || 0}

      {:error, reason} ->
        raise GRPC.RPCError, status: :invalid_argument, message: inspect(reason)
    end
  end

  @spec translate(Langos.V1.TranslateRequest.t(), GRPC.Server.Stream.t()) ::
          Langos.V1.TextReply.t()
  def translate(request, _stream) do
    payload = %{"text" => request.text, "from" => request.from, "to" => request.to}

    case LangOS.translate(payload) do
      {:ok, resp} ->
        %Langos.V1.TextReply{
          text: resp["text"] || "",
          ir_json: Jason.encode!(resp["ir"] || %{}),
          latency_ms: resp["latency_ms"] || 0
        }

      {:error, reason} ->
        raise GRPC.RPCError, status: :invalid_argument, message: inspect(reason)
    end
  end
end

defmodule LangOS.GRPC.Endpoint do
  @moduledoc false
  use GRPC.Endpoint

  run(LangOS.GRPC.Server)
end
