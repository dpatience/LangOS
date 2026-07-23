import Config

root = Path.expand("..", __DIR__)

config :langos,
  config_file: Path.join(root, "config/dev.json"),
  cache_enabled: false
