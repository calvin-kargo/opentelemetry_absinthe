defmodule OpentelemetryAbsinthe.ResolveInstrumentation do
  @moduledoc """
  Module for automatic instrumentation of Absinthe resolution, field level.

  It works by listening to [:absinthe, :resolve, :operation, :start/:stop] telemetry events,
  which are emitted by Absinthe only since v1.5; therefore it won't work on previous versions.

  (you can still call `OpentelemetryAbsinthe.ResolveInstrumentation.setup()` in your application startup
  code, it just won't do anything.)
  """
  require Record

  @tracer_id __MODULE__

  @default_config [
    resolve_span_name: "absinthe graphql resolve",
    additional_attributes: %{}
  ]

  def setup(instrumentation_opts \\ []) do
    config =
      @default_config
      |> Keyword.merge(Application.get_env(:opentelemetry_absinthe, :trace_options, []))
      |> Keyword.merge(instrumentation_opts)
      |> Enum.into(%{})

    :telemetry.attach(
      {__MODULE__, :resolution_start},
      [:absinthe, :resolve, :field, :start],
      &__MODULE__.handle_resolution_start/4,
      config
    )

    :telemetry.attach(
      {__MODULE__, :resolution_stop},
      [:absinthe, :resolve, :field, :stop],
      &__MODULE__.handle_resolution_stop/4,
      config
    )
  end

  def teardown do
    :telemetry.detach({__MODULE__, :resolution_start})
    :telemetry.detach({__MODULE__, :resolution_stop})
  end

  def handle_resolution_start(_event_name, _measurements, metadata, config) do
    field_name = safe_string_to_atom(metadata.resolution.definition.name)
    field_paths = Absinthe.Resolution.path(metadata.resolution)
    full_field_path = Enum.map(field_paths, fn field -> safe_string_to_atom(field) end)

    name_field_path =
      field_paths
      |> Enum.filter(fn path -> not is_integer(path) end)
      |> Enum.map(fn field -> safe_string_to_atom(field) end)

    additional_attributes = Map.new(config.additional_attributes)

    attributes =
      %{
        "graphql.field.name": safe_string_to_atom(metadata.resolution.definition.name),
        "graphql.field.alias": safe_string_to_atom(metadata.resolution.definition.alias),
        "graphql.full_field_path": full_field_path,
        "graphql.name_field_path": name_field_path
      }
      |> Map.merge(additional_attributes)

    execution_ctx =
      OpentelemetryAbsinthe.Registry.get_absinthe_execution_span() || OpenTelemetry.Tracer.current_span_ctx()

    OpenTelemetry.Tracer.set_current_span(execution_ctx)

    OpentelemetryTelemetry.start_telemetry_span(@tracer_id, :"#{config.resolve_span_name} #{field_name}", metadata, %{
      kind: :server,
      attributes: attributes
    })
  end

  def handle_resolution_stop(_event_name, _measurements, data, _config) do
    OpentelemetryTelemetry.end_telemetry_span(@tracer_id, data)
  end

  def safe_string_to_atom(string) when is_binary(string), do: String.to_atom(string)
  def safe_string_to_atom(any_else), do: any_else
end
