defmodule Mix.Tasks.Patience do
  @moduledoc """
  Alias for the LangOS CLI (`mix langos`). Same commands, branded as `patience` in help text.

      mix patience serve
      mix patience understand --text "Register Clarissa in Biology A1."
  """
  use Mix.Task

  @shortdoc "LangOS CLI (patience alias for mix langos)"

  @impl true
  def run(args), do: LangOS.CLI.main(args)
end
