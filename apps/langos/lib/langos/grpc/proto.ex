defmodule Langos.V1.UnderstandRequest do
  @moduledoc "Mirror of schemas/langos.proto — UnderstandRequest."
  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :text, 1, type: :string
  field :locale, 2, type: :string
end

defmodule Langos.V1.ExpressRequest do
  @moduledoc "Mirror of schemas/langos.proto — ExpressRequest."
  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :template, 1, type: :string
  field :locale, 2, type: :string
  field :data_json, 3, type: :string
end

defmodule Langos.V1.TranslateRequest do
  @moduledoc "Mirror of schemas/langos.proto — TranslateRequest."
  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :text, 1, type: :string
  field :from, 2, type: :string
  field :to, 3, type: :string
end

defmodule Langos.V1.IRReply do
  @moduledoc "Mirror of schemas/langos.proto — IRReply."
  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :ir_json, 1, type: :string
  field :language, 2, type: :string
  field :latency_ms, 3, type: :int64
end

defmodule Langos.V1.TextReply do
  @moduledoc "Mirror of schemas/langos.proto — TextReply."
  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :text, 1, type: :string
  field :ir_json, 2, type: :string
  field :latency_ms, 3, type: :int64
end

defmodule Langos.V1.LangOS.Service do
  @moduledoc "Mirror of schemas/langos.proto — service langos.v1.LangOS."
  use GRPC.Service, name: "langos.v1.LangOS", protoc_gen_elixir_version: "0.14.0"

  rpc :Understand, Langos.V1.UnderstandRequest, Langos.V1.IRReply
  rpc :Express, Langos.V1.ExpressRequest, Langos.V1.TextReply
  rpc :Translate, Langos.V1.TranslateRequest, Langos.V1.TextReply
end

defmodule Langos.V1.LangOS.Stub do
  @moduledoc "gRPC client stub for langos.v1.LangOS."
  use GRPC.Stub, service: Langos.V1.LangOS.Service
end
