defmodule LangOSCompatAPITest do
  @moduledoc false
  use ExUnit.Case, async: false
  import Plug.Test
  import Plug.Conn, only: [put_req_header: 3]

  @router LangOS.API.Router
  @opts LangOS.API.Router.init([])

  defp post_json(path, body) do
    :post
    |> conn(path, Jason.encode!(body))
    |> put_req_header("content-type", "application/json")
    |> @router.call(@opts)
  end

  test "OpenAI-compatible /v1/chat/completions returns IR as assistant message" do
    conn =
      post_json("/v1/chat/completions", %{
        "model" => "gpt-4",
        "messages" => [
          %{"role" => "system", "content" => "You are helpful."},
          %{"role" => "user", "content" => "Register Clarissa in Biology A1."}
        ]
      })

    assert conn.status == 200
    body = Jason.decode!(conn.resp_body)

    assert body["object"] == "chat.completion"
    assert [choice] = body["choices"]
    assert choice["message"]["role"] == "assistant"
    assert choice["finish_reason"] == "stop"
    assert body["usage"]["total_tokens"] > 0

    ir = Jason.decode!(choice["message"]["content"])
    assert ir["version"] == "1.2"

    pred = Enum.find(ir["graph"]["nodes"], &(&1["type"] == "predicate"))
    assert pred["predicate"]["id"] == "ACT_000005"
  end

  test "Anthropic-compatible /v1/messages returns IR as text content" do
    conn =
      post_json("/v1/messages", %{
        "model" => "claude-3",
        "max_tokens" => 1024,
        "messages" => [
          %{"role" => "user", "content" => [%{"type" => "text", "text" => "Do you know me?"}]}
        ]
      })

    assert conn.status == 200
    body = Jason.decode!(conn.resp_body)

    assert body["type"] == "message"
    assert body["role"] == "assistant"
    assert body["stop_reason"] == "end_turn"
    assert [%{"type" => "text", "text" => ir_json}] = body["content"]

    ir = Jason.decode!(ir_json)
    assert ir["version"] == "1.2"
    assert ir["utterance_type"] == "question"
  end

  test "missing user message returns 400" do
    conn = post_json("/v1/chat/completions", %{"model" => "gpt-4", "messages" => []})
    assert conn.status == 400
  end
end
