import Config

root = Path.expand("..", __DIR__)

config :langos,
  config_file: Path.join(root, "config/dev.json")

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

if File.exists?("config/#{Mix.env()}.exs") do
  import_config "#{Mix.env()}.exs"
end
