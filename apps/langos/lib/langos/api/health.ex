defmodule LangOS.API.Health do
  @moduledoc false

  @started_at System.system_time(:second)

  def uptime_seconds do
    System.system_time(:second) - @started_at
  end
end
