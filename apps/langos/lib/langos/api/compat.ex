defmodule LangOS.API.Compat do
  @moduledoc """
  OpenAI and Anthropic compatible endpoints.
  Existing clients point their base URL at LangOS and receive Semantic IR
  as the assistant response — no external vendor is ever called.
  """

  alias LangOS.Native

  @spec chat_completions(map()) :: {:ok, map()} | {:error, term()}
  def chat_completions(params) do
    with {:ok, text} <- last_user_message(params["messages"]),
         {:ok, resp} <- LangOS.understand(understand_request(text, params)) do
      ir_json = Jason.encode!(resp["ir"])

      {:ok,
       %{
         "id" => "chatcmpl-" <> request_id(text),
         "object" => "chat.completion",
         "created" => System.os_time(:second),
         "model" => params["model"] || "langos-understand-1",
         "choices" => [
           %{
             "index" => 0,
             "message" => %{"role" => "assistant", "content" => ir_json},
             "finish_reason" => "stop"
           }
         ],
         "usage" => usage(text, ir_json, :openai)
       }}
    end
  end

  @spec messages(map()) :: {:ok, map()} | {:error, term()}
  def messages(params) do
    with {:ok, text} <- last_user_message(params["messages"]),
         {:ok, resp} <- LangOS.understand(understand_request(text, params)) do
      ir_json = Jason.encode!(resp["ir"])

      {:ok,
       %{
         "id" => "msg_" <> request_id(text),
         "type" => "message",
         "role" => "assistant",
         "content" => [%{"type" => "text", "text" => ir_json}],
         "model" => params["model"] || "langos-understand-1",
         "stop_reason" => "end_turn",
         "usage" => usage(text, ir_json, :anthropic)
       }}
    end
  end

  defp understand_request(text, params) do
    case params["langos_locale"] do
      nil -> %{"text" => text}
      locale -> %{"text" => text, "locale" => locale}
    end
  end

  defp last_user_message(messages) when is_list(messages) do
    messages
    |> Enum.reverse()
    |> Enum.find_value(fn
      %{"role" => "user", "content" => content} when is_binary(content) -> content
      %{"role" => "user", "content" => blocks} when is_list(blocks) -> text_from_blocks(blocks)
      _ -> nil
    end)
    |> case do
      nil -> {:error, :no_user_message}
      text -> {:ok, text}
    end
  end

  defp last_user_message(_), do: {:error, :no_user_message}

  defp text_from_blocks(blocks) do
    blocks
    |> Enum.filter(&(is_map(&1) and &1["type"] == "text"))
    |> Enum.map_join(" ", & &1["text"])
    |> case do
      "" -> nil
      text -> text
    end
  end

  defp request_id(text) do
    :crypto.hash(:sha256, "#{text}:#{System.os_time(:nanosecond)}")
    |> Base.encode16(case: :lower)
    |> binary_part(0, 24)
  end

  defp usage(input, output, :openai) do
    prompt = Native.safe_count_tokens(input)
    completion = Native.safe_count_tokens(output)

    %{
      "prompt_tokens" => prompt,
      "completion_tokens" => completion,
      "total_tokens" => prompt + completion
    }
  end

  defp usage(input, output, :anthropic) do
    %{
      "input_tokens" => Native.safe_count_tokens(input),
      "output_tokens" => Native.safe_count_tokens(output)
    }
  end
end
