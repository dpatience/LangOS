defmodule LangOS.CLI do
  @moduledoc """
  Patience CLI — the LangOS command-line interface.
  Named after Patience, who created LangOS.
  """
  @switches [config: :string, text: :string, template: :string, data: :string, from: :string, to: :string]
  @aliases [c: :config]

  def main(argv) do
    case argv do
      ["understand" | rest] -> cmd_understand(rest)
      ["express" | rest] -> cmd_express(rest)
      ["serve" | rest] -> cmd_serve(rest)
      ["languages", "list"] -> cmd_languages_list()
      ["engines", "list"] -> cmd_engines_list()
      ["version"] -> cmd_version()
      _ -> usage()
    end
  end

  defp cmd_understand(args) do
    {opts, _, _} = OptionParser.parse(args, switches: @switches, aliases: @aliases)
    text = opts[:text] || IO.read(:stdio, :line) |> String.trim()

    ensure_services()

    case LangOS.understand(%{"text" => text}) do
      {:ok, resp} -> IO.puts(Jason.encode!(resp, pretty: true))
      {:error, err} -> exit_error(err)
    end
  end

  defp cmd_express(args) do
    {opts, _, _} = OptionParser.parse(args, switches: @switches, aliases: @aliases)
    template = opts[:template] || "success"

    data =
      case opts[:data] do
        nil -> %{}
        path -> path |> File.read!() |> Jason.decode!()
      end

    ensure_services()

    case LangOS.express(%{"template" => template, "locale" => "en", "data" => data}) do
      {:ok, resp} -> IO.puts(Jason.encode!(resp, pretty: true))
      {:error, err} -> exit_error(err)
    end
  end

  defp cmd_serve(args) do
    {opts, _, _} = OptionParser.parse(args, switches: @switches, aliases: @aliases)

    if path = opts[:config] do
      Application.put_env(:langos, :config_file, path)
    end

    IO.puts("patience: Starting LangOS v#{LangOS.IR.version()}...")
    {:ok, _} = Application.ensure_all_started(:langos)
    port = LangOS.Config.get(["server", "http", "port"], 9473)
    IO.puts("patience: Listening on http://127.0.0.1:#{port}")
    IO.puts("patience: Semantic IR #{LangOS.IR.version()} — graph-first, language-independent")
    Process.sleep(:infinity)
  end

  defp cmd_version do
    IO.puts("patience v#{LangOS.IR.version()} (LangOS Semantic IR)")
  end

  defp cmd_languages_list do
    ensure_services()
    packs = LangOS.LanguagePack.Registry.list()
    IO.puts(Jason.encode!(packs, pretty: true))
  end

  defp cmd_engines_list do
    ensure_services()
    engines = LangOS.Engine.Registry.list()
    IO.puts(Jason.encode!(engines, pretty: true))
  end

  defp ensure_services do
    unless Process.whereis(LangOS.Config) do
      {:ok, _} = LangOS.Config.start_link([])
    end

    for mod <- [LangOS.Cache, LangOS.Engine.Registry, LangOS.LanguagePack.Registry, LangOS.Pipeline.Supervisor] do
      unless Process.whereis(mod) do
        {:ok, _} = apply(mod, :start_link, [])
      end
    end
  end

  defp exit_error(err) do
    IO.puts(:stderr, "patience: error — #{inspect(err)}")
    System.halt(1)
  end

  defp usage do
    IO.puts("""
    patience — LangOS CLI (by Patience)

      patience understand --text "Register Clarissa in Biology A1"
      patience express --template missing_fields --data fields.json
      patience serve [--config config/dev.json]
      patience languages list
      patience engines list
      patience version
    """)

    System.halt(1)
  end
end
