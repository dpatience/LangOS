defmodule LangOS.MCP.Server do
  @moduledoc """
  Model Context Protocol transport — JSON-RPC 2.0 over stdio.

  Any MCP client (agents, IDEs, orchestration frameworks) can call LangOS
  as a set of tools without HTTP. Per the transport-independence principle,
  this is a thin adapter over the same core runtime as the native API:

      patience mcp

  Exposed tools: `langos_understand`, `langos_understand_document`,
  `langos_express`, `langos_translate`.
  """

  @protocol_version "2025-06-18"
  @server_info %{"name" => "langos", "version" => "0.1.0"}

  @tools [
    %{
      "name" => "langos_understand",
      "description" =>
        "Parse human text (any installed language) into LangOS Semantic IR v1.2 — " <>
          "a language-independent semantic graph of predicates, concepts, references, and roles.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "text" => %{"type" => "string", "description" => "The text to understand"},
          "locale" => %{"type" => "string", "description" => "Optional locale hint (en, fr, rw). Omit for automatic language detection."}
        },
        "required" => ["text"]
      }
    },
    %{
      "name" => "langos_understand_document",
      "description" =>
        "Parse a multi-sentence document. Returns one Semantic IR per semantic unit " <>
          "with coreference slots linking references to entities from earlier units.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "text" => %{"type" => "string"},
          "locale" => %{"type" => "string"}
        },
        "required" => ["text"]
      }
    },
    %{
      "name" => "langos_express",
      "description" => "Generate natural language in a target locale from a template and data.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "template" => %{"type" => "string"},
          "locale" => %{"type" => "string"},
          "data" => %{"type" => "object"}
        },
        "required" => ["template"]
      }
    },
    %{
      "name" => "langos_translate",
      "description" => "Translate text between locales through the Semantic IR pivot.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "text" => %{"type" => "string"},
          "from" => %{"type" => "string"},
          "to" => %{"type" => "string"}
        },
        "required" => ["text", "from", "to"]
      }
    }
  ]

  @doc "Blocking stdio loop: one JSON-RPC message per line."
  @spec run() :: no_return()
  def run do
    case IO.read(:stdio, :line) do
      :eof ->
        :ok

      {:error, _} ->
        :ok

      line ->
        line
        |> String.trim()
        |> handle_line()

        run()
    end
  end

  defp handle_line(""), do: :ok

  defp handle_line(line) do
    case Jason.decode(line) do
      {:ok, message} ->
        case handle_message(message) do
          {:reply, reply} -> IO.puts(Jason.encode!(reply))
          :noreply -> :ok
        end

      {:error, _} ->
        IO.puts(Jason.encode!(error_reply(nil, -32700, "parse error")))
    end
  end

  @doc "Pure JSON-RPC dispatch — testable without stdio."
  @spec handle_message(map()) :: {:reply, map()} | :noreply
  def handle_message(%{"method" => "initialize", "id" => id}) do
    {:reply,
     result_reply(id, %{
       "protocolVersion" => @protocol_version,
       "capabilities" => %{"tools" => %{}},
       "serverInfo" => @server_info
     })}
  end

  def handle_message(%{"method" => "notifications/" <> _}), do: :noreply

  def handle_message(%{"method" => "ping", "id" => id}) do
    {:reply, result_reply(id, %{})}
  end

  def handle_message(%{"method" => "tools/list", "id" => id}) do
    {:reply, result_reply(id, %{"tools" => @tools})}
  end

  def handle_message(%{"method" => "tools/call", "id" => id, "params" => params}) do
    name = params["name"]
    args = params["arguments"] || %{}

    case call_tool(name, args) do
      {:ok, payload} ->
        {:reply,
         result_reply(id, %{
           "content" => [%{"type" => "text", "text" => Jason.encode!(payload)}],
           "isError" => false
         })}

      {:error, reason} ->
        {:reply,
         result_reply(id, %{
           "content" => [%{"type" => "text", "text" => Jason.encode!(%{"error" => inspect(reason)})}],
           "isError" => true
         })}
    end
  end

  def handle_message(%{"method" => _method, "id" => id}) do
    {:reply, error_reply(id, -32601, "method not found")}
  end

  def handle_message(_), do: :noreply

  defp call_tool("langos_understand", args) do
    LangOS.understand(Map.take(args, ["text", "locale"]))
  end

  defp call_tool("langos_understand_document", args) do
    LangOS.understand_document(Map.take(args, ["text", "locale"]))
  end

  defp call_tool("langos_express", args) do
    LangOS.express(Map.take(args, ["template", "locale", "data"]))
  end

  defp call_tool("langos_translate", args) do
    LangOS.translate(Map.take(args, ["text", "from", "to"]))
  end

  defp call_tool(name, _args), do: {:error, {:unknown_tool, name}}

  defp result_reply(id, result) do
    %{"jsonrpc" => "2.0", "id" => id, "result" => result}
  end

  defp error_reply(id, code, message) do
    %{"jsonrpc" => "2.0", "id" => id, "error" => %{"code" => code, "message" => message}}
  end
end
