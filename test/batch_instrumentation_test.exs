defmodule OpentelemetryAbsintheTest.BatchInstrumentation do
  use ExUnit.Case
  alias AbsinthePlug.Test.Schema
  require Record

  doctest OpentelemetryAbsinthe.BatchInstrumentation

  for {name, spec} <- Record.extract_all(from_lib: "opentelemetry/include/otel_span.hrl") do
    Record.defrecord(name, spec)
  end

  @query """
  query($isbn: String!) {
    book(isbn: $isbn) {
      title
      author {
        name
        age
        profilePicture
      }
    }
  }
  """

  setup do
    Application.delete_env(:opentelemetry_absinthe, :trace_options)
    OpentelemetryAbsinthe.Instrumentation.teardown()
    OpentelemetryAbsinthe.ResolveInstrumentation.teardown()
    OpentelemetryAbsinthe.BatchInstrumentation.teardown()
    :otel_batch_processor.set_exporter(:otel_exporter_pid, self())
  end

  describe "batch field tracing" do
    test "able to trace batch field data" do
      OpentelemetryAbsinthe.BatchInstrumentation.setup()
      {:ok, _} = Absinthe.run(@query, Schema, variables: %{"isbn" => "A1"})
      assert_receive {:span, data = span(attributes: attributes)}, 5000

      assert [
               :"graphql.batch.function"
             ] = attributes |> keys() |> Enum.sort()

      assert data(attributes)[:"graphql.batch.function"] == "Elixir.AbsinthePlug.Test.Schema batch_get_profile_picture"
      assert span(data, :name) == :"absinthe graphql batch Elixir.AbsinthePlug.Test.Schema batch_get_profile_picture"
    end

    test "additional attributes are included in spans" do
      additional_attributes = [env: "test"]
      OpentelemetryAbsinthe.BatchInstrumentation.setup(additional_attributes: additional_attributes)
      {:ok, _} = Absinthe.run(@query, Schema, variables: %{"isbn" => "A1"})
      assert_receive {:span, span(attributes: attributes)}, 5000

      assert data(attributes)[:env] == "test"
    end
  end

  defp keys(attributes_record), do: attributes_record |> elem(4) |> Map.keys()
  defp data(attributes_record), do: attributes_record |> elem(4)
end
