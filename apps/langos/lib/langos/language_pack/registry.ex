defmodule LangOS.LanguagePack.Registry do
  @moduledoc """
  Loads installed language packs from the packs directory.
  Serves patterns, templates, verb maps, and pronoun maps.
  """
  use GenServer

  alias LangOS.Config

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec list() :: [map()]
  def list, do: GenServer.call(__MODULE__, :list)

  @spec get(String.t()) :: {:ok, map()} | {:error, :not_found}
  def get(id), do: GenServer.call(__MODULE__, {:get, id})

  @spec patterns_json(String.t()) :: {:ok, String.t()} | {:error, term()}
  def patterns_json(id) do
    with {:ok, pack} <- get(id),
         {:ok, body} <- File.read(pack.patterns_file) do
      {:ok, body}
    end
  end

  @spec express_template(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def express_template(pack_id, template_name) do
    with {:ok, pack} <- get(pack_id) do
      path = Path.join(pack.templates_dir, "#{template_name}.json")

      case File.read(path) do
        {:ok, body} -> Jason.decode(body)
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @spec verb_map(String.t()) :: map()
  def verb_map(id) do
    case get(id) do
      {:ok, pack} -> pack.verb_map
      _ -> %{}
    end
  end

  @spec pronoun_map(String.t()) :: map()
  def pronoun_map(id) do
    case get(id) do
      {:ok, pack} -> pack.pronoun_map
      _ -> %{}
    end
  end

  @doc """
  Language-detection signals declared by the pack:
  `words` (high-frequency function words), `strip_prefixes` (morphological
  prefixes to strip before verb lookup, e.g. Kinyarwanda ku-/gu-/n-),
  and `subject_prefixes` (bound subject markers -> reserved references).
  """
  @spec detection(String.t()) :: map()
  def detection(id) do
    case get(id) do
      {:ok, pack} -> pack.detection
      _ -> %{}
    end
  end

  @spec installed_ids() :: [String.t()]
  def installed_ids do
    list() |> Enum.map(& &1.id)
  end

  @doc """
  Hot-install a language pack at runtime. Loads the pack from the packs
  directory and adds it to the registry. Returns {:ok, pack_info} or
  {:error, reason}.
  """
  @spec install(String.t()) :: {:ok, map()} | {:error, term()}
  def install(id) do
    GenServer.call(__MODULE__, {:install, id})
  end

  @impl true
  def init(_opts) do
    packs_dir =
      case Process.whereis(Config) do
        nil -> Path.expand("packs", File.cwd!())
        _ -> init_packs_dir()
      end

    installed =
      case Process.whereis(Config) do
        nil -> ["en"]
        _ -> Config.get(["language_packs", "installed"], ["en"])
      end

    packs =
      installed
      |> Enum.map(&load_pack(&1, packs_dir))
      |> Enum.reject(&is_nil/1)
      |> Map.new(fn pack -> {pack.id, pack} end)

    {:ok, %{packs: packs, packs_dir: packs_dir}}
  end

  @impl true
  def handle_call(:list, _from, %{packs: packs} = state) do
    list =
      packs
      |> Map.values()
      |> Enum.map(fn p ->
        %{id: p.id, name: p.name, version: p.version, capabilities: p.capabilities}
      end)

    {:reply, list, state}
  end

  def handle_call({:get, id}, _from, %{packs: packs} = state) do
    reply =
      case Map.fetch(packs, id) do
        {:ok, pack} -> {:ok, pack}
        :error -> {:error, :not_found}
      end

    {:reply, reply, state}
  end

  def handle_call({:install, id}, _from, %{packs: packs, packs_dir: packs_dir} = state) do
    if Map.has_key?(packs, id) do
      info = Map.get(packs, id)
      {:reply, {:ok, %{id: info.id, name: info.name, status: :already_installed}}, state}
    else
      case load_pack(id, packs_dir) do
        nil ->
          {:reply, {:error, {:pack_not_found, id}}, state}

        pack ->
          LangOS.Grammar.reload(id)
          new_packs = Map.put(packs, id, pack)

          {:reply,
           {:ok, %{id: pack.id, name: pack.name, version: pack.version, status: :installed}},
           %{state | packs: new_packs}}
      end
    end
  end

  defp init_packs_dir do
    case Config.get(["packs_dir"]) do
      nil -> Path.expand("packs", File.cwd!())
      dir -> Path.expand(dir, File.cwd!())
    end
  end

  defp load_pack(id, packs_dir) do
    root = Path.join(packs_dir, id)
    manifest_path = Path.join(root, "manifest.json")
    patterns_path = Path.join(root, "patterns/commands.json")

    with {:ok, body} <- File.read(manifest_path),
         {:ok, manifest} <- Jason.decode(body) do
      {verb_map, pronoun_map, detection} = load_mappings(patterns_path)

      %{
        id: id,
        name: manifest["name"] || String.upcase(id),
        version: manifest["version"] || "1.0.0",
        capabilities: manifest["capabilities"] || ["understand", "express"],
        root: root,
        patterns_file: patterns_path,
        templates_dir: Path.join(root, "templates/express"),
        verb_map: verb_map,
        pronoun_map: pronoun_map,
        detection: detection
      }
    else
      _ -> nil
    end
  end

  defp load_mappings(patterns_path) do
    case File.read(patterns_path) do
      {:ok, body} ->
        case Jason.decode(body) do
          {:ok, data} ->
            {Map.get(data, "verb_map", %{}), Map.get(data, "pronoun_map", %{}),
             Map.get(data, "detection", %{})}

          _ ->
            {%{}, %{}, %{}}
        end

      _ ->
        {%{}, %{}, %{}}
    end
  end
end
