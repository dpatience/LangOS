defmodule LangOS.Benchmark do
  @moduledoc """
  Benchmark suite and evaluation harness.

  Runs a JSONL corpus (same shape as pack golden files) through the full
  understand pipeline with the cache disabled, and reports accuracy and
  latency percentiles per engine:

      patience benchmark --file bench/corpus.jsonl

  Corpus line format:

      {"input": {"text": "...", "locale": "en"},
       "expected": {"vocab_id": "ACT_000005", "utterance_type": "command",
                    "language": "en"}}

  Every `expected` key is optional; only present keys are checked.
  CI gates on accuracy and on latency regression against a saved baseline.
  """

  @spec run(String.t()) :: {:ok, map()} | {:error, term()}
  def run(path) do
    with {:ok, cases} <- load_corpus(path) do
      cache_was = Application.get_env(:langos, :cache_enabled, true)
      Application.put_env(:langos, :cache_enabled, false)

      # Warm persistent terms (lexicon, model, vocabulary) so the first
      # measured case does not pay one-time load cost.
      _ = LangOS.understand(%{"text" => "hello"})

      results = Enum.map(cases, &run_case/1)
      Application.put_env(:langos, :cache_enabled, cache_was)

      {:ok, report(results)}
    end
  end

  @spec print(map()) :: :ok
  def print(report) do
    IO.puts("""

    patience benchmark — #{report["total"]} cases
    ─────────────────────────────────────────────
    accuracy   #{report["passed"]}/#{report["total"]} (#{report["accuracy"]}%)
    latency    p50 #{report["latency"]["p50_ms"]}ms · p95 #{report["latency"]["p95_ms"]}ms · max #{report["latency"]["max_ms"]}ms
    """)

    IO.puts("    engines:")

    Enum.each(report["engines"], fn {engine, count} ->
      IO.puts("      #{String.pad_trailing(engine, 20)} #{count}")
    end)

    if report["failures"] != [] do
      IO.puts("\n    failures:")

      Enum.each(report["failures"], fn f ->
        IO.puts("      ✗ #{f["text"]}")
        IO.puts("        #{f["reason"]}")
      end)
    end

    IO.puts("")
    :ok
  end

  defp load_corpus(path) do
    case File.read(resolve_path(path)) do
      {:ok, body} ->
        cases =
          body
          |> String.split("\n", trim: true)
          |> Enum.map(&Jason.decode!/1)

        {:ok, cases}

      {:error, reason} ->
        {:error, {:corpus_unreadable, path, reason}}
    end
  end

  # Relative corpus paths resolve against the cwd or the repo root
  # (tests and releases run from different directories).
  defp resolve_path(path) do
    candidates = [
      Path.expand(path, File.cwd!()),
      Path.expand(Path.join("../../../..", path), __DIR__)
    ]

    Enum.find(candidates, path, &File.exists?/1)
  end

  defp run_case(%{"input" => input, "expected" => expected}) do
    started = System.monotonic_time(:microsecond)
    result = LangOS.understand(input)
    latency_us = System.monotonic_time(:microsecond) - started

    case result do
      {:ok, resp} ->
        ir = resp["ir"]
        failures = check(expected, resp, ir)

        %{
          text: input["text"],
          latency_us: latency_us,
          engine: get_in(ir, ["meta", "engine", "parser"]) || "unknown",
          pass: failures == [],
          reason: Enum.join(failures, "; ")
        }

      {:error, reason} ->
        %{
          text: input["text"],
          latency_us: latency_us,
          engine: "error",
          pass: false,
          reason: "pipeline error: #{inspect(reason)}"
        }
    end
  end

  defp check(expected, resp, ir) do
    predicate =
      ir["graph"]["nodes"]
      |> Enum.find(&(&1["type"] == "predicate"))
      |> get_in(["predicate", "id"])

    checks = [
      {"vocab_id", predicate},
      {"utterance_type", ir["utterance_type"]},
      {"language", resp["language"]}
    ]

    for {key, actual} <- checks,
        Map.has_key?(expected, key),
        expected[key] != actual do
      "#{key}: expected #{expected[key]}, got #{actual}"
    end
  end

  defp report(results) do
    latencies = results |> Enum.map(& &1.latency_us) |> Enum.sort()
    passed = Enum.count(results, & &1.pass)
    total = length(results)

    %{
      "total" => total,
      "passed" => passed,
      "accuracy" => Float.round(passed / max(total, 1) * 100, 1),
      "latency" => %{
        "p50_ms" => percentile_ms(latencies, 0.50),
        "p95_ms" => percentile_ms(latencies, 0.95),
        "max_ms" => percentile_ms(latencies, 1.0),
        "mean_ms" => Float.round(Enum.sum(latencies) / max(total, 1) / 1000, 2)
      },
      "engines" => results |> Enum.frequencies_by(& &1.engine) |> Enum.sort(),
      "failures" =>
        results
        |> Enum.reject(& &1.pass)
        |> Enum.map(&%{"text" => &1.text, "reason" => &1.reason})
    }
  end

  defp percentile_ms([], _p), do: 0.0

  defp percentile_ms(sorted, p) do
    index = min(round(p * length(sorted)) - 1, length(sorted) - 1) |> max(0)
    Float.round(Enum.at(sorted, index) / 1000, 2)
  end
end
