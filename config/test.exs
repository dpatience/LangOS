import Config

root = Path.expand("..", __DIR__)

# Tests run on their own ports (9573 http / 9574 grpc) so the suite never
# collides with a dev server on 9473/9474.
config :langos,
  config_file: Path.join(root, "config/test.json")
