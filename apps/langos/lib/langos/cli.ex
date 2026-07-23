defmodule LangOS.CLI do
  @moduledoc """
  Patience CLI — the LangOS command-line interface.
  Named after Patience, who created LangOS.
  """
  @switches [
    config: :string,
    text: :string,
    template: :string,
    data: :string,
    from: :string,
    to: :string,
    file: :string,
    locale: :string,
    tone: :string,
    document: :boolean
  ]
  @aliases [c: :config]

  def main(argv) do
    case argv do
      ["understand" | rest] -> cmd_understand(rest)
      ["express" | rest] -> cmd_express(rest)
      ["serve" | rest] -> cmd_serve(rest)
      ["mcp" | rest] -> cmd_mcp(rest)
      ["benchmark" | rest] -> cmd_benchmark(rest)
      ["install", "language", id | _] -> cmd_install_language(id)
      ["train" | rest] -> cmd_train(rest)
      ["setup" | rest] -> cmd_setup(rest)
      ["languages", "list"] -> cmd_languages_list()
      ["engines", "list"] -> cmd_engines_list()
      ["plugins", "list"] -> cmd_plugins_list()
      ["version"] -> cmd_version()
      _ -> usage()
    end
  end

  defp cmd_understand(args) do
    {opts, _, _} = OptionParser.parse(args, switches: @switches, aliases: @aliases)

    text =
      cond do
        opts[:file] -> File.read!(opts[:file])
        opts[:text] -> opts[:text]
        true -> IO.read(:stdio, :line) |> String.trim()
      end

    ensure_services()

    request =
      %{"text" => text}
      |> then(fn req -> if opts[:locale], do: Map.put(req, "locale", opts[:locale]), else: req end)

    result =
      if opts[:document] || opts[:file] do
        LangOS.understand_document(request)
      else
        LangOS.understand(request)
      end

    case result do
      {:ok, resp} -> IO.puts(Jason.encode!(resp, pretty: true))
      {:error, err} -> exit_error(err)
    end
  end

  defp cmd_express(args) do
    {opts, _, _} = OptionParser.parse(args, switches: @switches, aliases: @aliases)
    template = opts[:template] || "success"
    locale = opts[:locale] || "en"

    data =
      case opts[:data] do
        nil -> %{}
        value -> parse_json_or_file!(value)
      end

    ensure_services()

    request = %{"template" => template, "locale" => locale, "data" => data}
    request = if opts[:tone], do: Map.put(request, "tone", opts[:tone]), else: request

    case LangOS.express(request) do
      {:ok, resp} -> IO.puts(Jason.encode!(resp, pretty: true))
      {:error, err} -> exit_error(err)
    end
  end

  defp parse_json_or_file!(value) do
    trimmed = String.trim(value)

    cond do
      String.starts_with?(trimmed, "{") or String.starts_with?(trimmed, "[") ->
        case Jason.decode(trimmed) do
          {:ok, data} -> data
          {:error, err} -> exit_error({:invalid_json, err})
        end

      File.exists?(value) ->
        value |> File.read!() |> Jason.decode!()

      true ->
        exit_error({:data_not_found, "expected inline JSON or an existing file path", value})
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

  defp cmd_mcp(args) do
    {opts, _, _} = OptionParser.parse(args, switches: @switches, aliases: @aliases)

    if path = opts[:config] do
      Application.put_env(:langos, :config_file, path)
    end

    ensure_services()
    LangOS.MCP.Server.run()
  end

  defp cmd_benchmark(args) do
    {opts, _, _} = OptionParser.parse(args, switches: @switches, aliases: @aliases)
    path = opts[:file] || "bench/corpus.jsonl"

    ensure_services()

    case LangOS.Benchmark.run(path) do
      {:ok, report} ->
        LangOS.Benchmark.print(report)
        if report["accuracy"] < 100.0, do: System.halt(1)

      {:error, err} ->
        exit_error(err)
    end
  end

  defp cmd_plugins_list do
    ensure_services()
    IO.puts(Jason.encode!(LangOS.VocabPlugin.installed(), pretty: true))
  end

  defp cmd_version do
    IO.puts("patience v#{LangOS.IR.version()} (LangOS Semantic IR)")
  end

  defp cmd_install_language(id) do
    ensure_services()

    case LangOS.LanguagePack.Registry.install(id) do
      {:ok, %{status: :already_installed, name: name}} ->
        IO.puts("patience: #{name} (#{id}) is already installed.")
        maybe_prompt_train(id)

      {:ok, %{status: :installed, name: name, version: version}} ->
        IO.puts("patience: Installed #{name} (#{id}) v#{version}.")
        IO.puts("patience: Grammar, vocabulary, and templates loaded.")
        maybe_prompt_train(id)

      {:error, {:pack_not_found, _}} ->
        IO.puts(:stderr, "patience: Language pack \"#{id}\" not found in packs directory.")
        IO.puts(:stderr, "patience: Bundled packs: en, fr, de, tr, rw")
        IO.puts(:stderr, "patience: Create packs/#{id}/ or download when pack registry is enabled.")
        System.halt(1)

      {:error, err} ->
        exit_error(err)
    end
  end

  defp maybe_prompt_train(lang) do
    model_path = Path.expand("models/#{lang}/intent.json", File.cwd!())

    unless File.exists?(model_path) do
      IO.puts("patience: No trained model for \"#{lang}\" yet.")
      IO.puts("patience: Run: mix patience train --lang #{lang}")
    end
  end

  defp cmd_train(args) do
    {opts, rest, _} = OptionParser.parse(args, switches: [lang: :string, all: :boolean])

    lang_arg =
      opts[:lang] ||
        case rest do
          [code | _] when is_binary(code) -> code
          _ -> nil
        end

    cond do
      opts[:all] ->
        run_python_train(["--all"])

      is_binary(lang_arg) ->
        run_python_train(["--lang", lang_arg])

      true ->
        IO.puts(:stderr, "patience: usage: patience train --lang fr | --all")
        System.halt(1)
    end
  end

  defp run_python_train(argv) do
    root = repo_root()

    cmd =
      if File.exists?(Path.join(root, "python/langos_train/pyproject.toml")) do
        {"python3", ["-m", "langos_train.build_pack" | argv]}
      else
        exit_error(:training_not_available)
      end

    {exe, py_args} = cmd
    IO.puts("patience: Training statistical models (#{Enum.join(py_args, " ")})...")

    case System.cmd(exe, py_args, cd: root, env: [{"PYTHONPATH", Path.join(root, "python/langos_train")}]) do
      {out, 0} ->
        IO.write(out)
        IO.puts("patience: Training complete. Restart serve or run understand to pick up models.")

      {out, code} ->
        IO.write(:stderr, out)
        exit_error({:train_failed, code})
    end
  end

  defp cmd_setup(args) do
    {opts, _, _} = OptionParser.parse(args, switches: [lang: :string, list: :boolean])

    if opts[:list] do
      IO.puts("Available language packs: en, fr, de, tr, rw")
      System.halt(0)
    end

    ensure_services()
    packs = LangOS.LanguagePack.Registry.list()

    IO.puts("""
    patience setup — choose your default language
    """)

    Enum.with_index(packs, 1)
    |> Enum.each(fn {p, i} -> IO.puts("  #{i}. #{p.name} (#{p.id})") end)

    chosen =
      cond do
        lang = opts[:lang] -> lang
        true -> IO.gets("Enter number or code [en]: ") |> String.trim()
      end

    id =
      cond do
        chosen == "" -> "en"
        chosen =~ ~r/^\d+$/ ->
          idx = String.to_integer(chosen) - 1
          packs |> Enum.at(idx) |> then(fn p -> p && p.id end) || "en"

        true ->
          chosen |> String.downcase()
      end

    config_path = Path.expand("config/langos.json", repo_root())
    update_default_language(config_path, id)
    LangOS.LanguagePack.Registry.install(id)

    model = Path.expand("models/#{id}/intent.json", repo_root())

    unless File.exists?(model) do
      IO.puts("patience: Training statistical model for #{id}...")
      run_python_train(["--lang", id])
    end

    IO.puts("patience: Default language set to #{id}. Run: mix patience serve")
  end

  defp update_default_language(config_path, lang) do
    config =
      case File.read(config_path) do
        {:ok, body} -> Jason.decode!(body)
        _ -> %{}
      end

    updated =
      config
      |> Map.put("language_packs", Map.merge(config["language_packs"] || %{}, %{
        "default" => lang,
        "installed" => Enum.uniq((config["language_packs"]["installed"] || ["en"]) ++ [lang])
      }))

    File.write!(config_path, Jason.encode!(updated, pretty: true) <> "\n")
  end

  defp repo_root do
    candidates = [
      File.cwd!(),
      Path.expand("../../../..", __DIR__)
    ]

    Enum.find(candidates, fn dir ->
      File.exists?(Path.join(dir, "schemas/semantic_vocabulary.json"))
    end) || File.cwd!()
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
      patience understand --file report.txt          # document mode (unit streaming pipeline)
      patience express --template missing_fields --tone formal --locale fr --data '{"entity":"Clarissa","fields":"age, language"}'
      patience express --template missing_fields --data fields.json
      patience install language de                 # load a language pack from packs/
      patience train --lang fr                     # build lexicon + intent model
      patience train --all                         # train en, fr, de, tr, rw
      patience setup [--lang fr]                   # first-run: pick default language
      patience serve [--config config/dev.json]
      patience mcp                                   # Model Context Protocol over stdio
      patience benchmark [--file bench/corpus.jsonl]
      patience languages list
      patience engines list
      patience plugins list
      patience version
    """)

    System.halt(1)
  end
end
