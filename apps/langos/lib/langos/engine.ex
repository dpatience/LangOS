defmodule LangOS.Engine do
  @moduledoc """
  Behaviour contract for LangOS inference engines.
  See docs/ENGINE_SPEC.md.
  """

  @type semantic_ir :: map()
  @type text :: String.t()
  @type tokens :: list()
  @type parse_tree :: map()
  @type opts :: keyword()

  @callback tokenize(text(), opts()) :: {:ok, tokens()} | {:error, term()}
  @callback parse(text(), opts()) :: {:ok, parse_tree()} | {:error, term()}
  @callback extract_meaning(parse_tree(), opts()) :: {:ok, semantic_ir()} | {:error, term()}
  @callback generate(map(), opts()) :: {:ok, text()} | {:error, term()}
  @callback capabilities() :: [atom()]
  @callback health() :: :ok | {:error, term()}

  defmacro __using__(_opts) do
    quote do
      @behaviour LangOS.Engine

      def tokenize(_text, _opts \\ []), do: {:error, :not_supported}
      def parse(_text, _opts \\ []), do: {:error, :not_supported}
      def extract_meaning(_tree, _opts \\ []), do: {:error, :not_supported}
      def generate(_input, _opts \\ []), do: {:error, :not_supported}

      defoverridable tokenize: 2, parse: 2, extract_meaning: 2, generate: 2
    end
  end
end
