defmodule Mix.Tasks.Langos do
  @moduledoc """
  LangOS CLI entry point: `mix langos understand --text "..."`.
  """
  use Mix.Task

  @shortdoc "LangOS command-line interface"

  @impl true
  def run(args), do: LangOS.CLI.main(args)
end
