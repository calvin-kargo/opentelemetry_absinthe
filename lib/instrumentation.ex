defmodule OpentelemetryAbsinthe.Instrumentation do
  @moduledoc """
  Module for automatic instrumentation of Absinthe execution.

  It works by listening to [:absinthe, :execute, :operation, :start/:stop] telemetry events,
  which are emitted by Absinthe only since v1.5; therefore it won't work on previous versions.

  (you can still call `OpentelemetryAbsinthe.Instrumentation.setup()` in your application startup
  code, it just won't do anything.)
  """

  alias OpenTelemetry.Span
  require Record
  import OpentelemetryAbsinthe.Macro

  @tracer_id __MODULE__

  @default_config [
    span_name: "absinthe graphql execute",
    trace_request_query: true,
    trace_request_variables: true,
    trace_response_result: false,
    trace_response_errors: true,
    additional_attributes: %{}
  ]

  def setup(instrumentation_opts \\ []) do
    config =
      @default_config
      |> Keyword.merge(Application.get_env(:opentelemetry_absinthe, :trace_options, []))
      |> Keyword.merge(instrumentation_opts)
      |> Enum.into(%{})

    :telemetry.attach(
      {__MODULE__, :operation_start},
      [:absinthe, :execute, :operation, :start],
      &__MODULE__.handle_operation_start/4,
      config
    )

    :telemetry.attach(
      {__MODULE__, :operation_stop},
      [:absinthe, :execute, :operation, :stop],
      &__MODULE__.handle_operation_stop/4,
      config
    )
  end

  def teardown do
    :telemetry.detach({__MODULE__, :operation_start})
    :telemetry.detach({__MODULE__, :operation_stop})
  end

  def handle_operation_start(_event_name, _measurements, metadata, config) do
    params = metadata |> Map.get(:options, []) |> Keyword.get(:params, %{})

    attributes =
      config.additional_attributes
      |> Map.new()
      |> put_if(
        config.trace_request_variables,
        :"graphql.request.variables",
        Jason.encode!(params["variables"])
      )
      |> put_if(
        config.trace_request_query,
        :"graphql.request.query",
        params["query"]
      )

    span =
      OpentelemetryTelemetry.start_telemetry_span(@tracer_id, :"#{config.span_name}", metadata, %{
        kind: :server,
        attributes: attributes
      })

    OpentelemetryAbsinthe.Registry.put_absinthe_execution_span(span)
  end

  def handle_operation_stop(_event_name, _measurements, data, config) do
    errors = data.blueprint.result[:errors]
    operation = Absinthe.Blueprint.current_operation(data.blueprint)

    result_attributes =
      %{}
      |> put_if(
        config.trace_response_result,
        :"graphql.response.result",
        Jason.encode!(data.blueprint.result)
      )
      |> put_if(
        config.trace_response_errors,
        :"graphql.response.errors",
        Jason.encode!(errors)
      )
      |> put_if(
        operation.name,
        :"graphql.operation.name",
        operation.name
      )
      |> put_if(
        operation.complexity,
        :"graphql.operation.complexity",
        operation.complexity
      )

    ctx = OpentelemetryTelemetry.set_current_telemetry_span(@tracer_id, data)

    case errors do
      nil -> :ok
      [] -> :ok
      _ -> Span.set_status(ctx, OpenTelemetry.status(:error, ""))
    end

    Span.set_attributes(ctx, result_attributes)

    OpentelemetryTelemetry.end_telemetry_span(@tracer_id, data)
  end
end
