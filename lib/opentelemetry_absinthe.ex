defmodule OpentelemetryAbsinthe do
  @moduledoc """
  OpentelemetryAbsinthe is an opentelemetry instrumentation library for Absinthe
  """

  def setup(opts \\ []) do
    OpentelemetryAbsinthe.Instrumentation.setup(opts)
    OpentelemetryAbsinthe.ResolveInstrumentation.setup(opts)
    OpentelemetryAbsinthe.BatchInstrumentation.setup(opts)
  end
end
