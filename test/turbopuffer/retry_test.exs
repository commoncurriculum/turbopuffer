defmodule Turbopuffer.RetryTest do
  use ExUnit.Case

  alias Turbopuffer.Client

  def report_attempt(_event, _measurements, %{request: request}, test_pid) do
    send(test_pid, {:attempt, request.host, request.port})
  end

  describe "retry?/1" do
    test "retries rate limits, server errors, and connection errors" do
      for status <- [408, 429, 500, 502, 503, 504] do
        assert Client.retry?({:ok, %Finch.Response{status: status}})
      end

      assert Client.retry?({:error, %Mint.TransportError{reason: :econnrefused}})
    end

    test "doesn't retry successes or client errors" do
      for status <- [200, 400, 401, 404, 422] do
        refute Client.retry?({:ok, %Finch.Response{status: status}})
      end
    end
  end

  describe "retry_delay/3" do
    test "backs off exponentially with jitter" do
      for attempt <- 0..3 do
        delay = Client.retry_delay({:error, %Mint.TransportError{reason: :closed}}, attempt, 100)
        assert delay >= 100 * Integer.pow(2, attempt)
        assert delay <= 100 * Integer.pow(2, attempt) + 100
      end
    end

    test "follows retry-after, capped at 30 seconds" do
      response = fn value ->
        {:ok, %Finch.Response{status: 429, headers: [{"retry-after", value}]}}
      end

      assert Client.retry_delay(response.("2"), 0, 100) == 2_000
      assert Client.retry_delay(response.("3600"), 0, 100) == 30_000
      assert Client.retry_delay(response.("soon"), 0, 100) in 100..200
    end
  end

  describe "requests" do
    setup do
      test_pid = self()
      handler = "retry-test-#{System.unique_integer([:positive])}"

      :telemetry.attach(
        handler,
        [:finch, :request, :start],
        &__MODULE__.report_attempt/4,
        test_pid
      )

      on_exit(fn -> :telemetry.detach(handler) end)
    end

    test "retry connection errors up to :max_retries" do
      client =
        Client.new(
          api_key: "test-key",
          base_url: "http://127.0.0.1:1",
          max_retries: 2,
          retry_delay: 1
        )

      assert {:error, %Mint.TransportError{reason: :econnrefused}} =
               Turbopuffer.list_namespaces(client)

      for _ <- 1..3, do: assert_received({:attempt, "127.0.0.1", 1})
      refute_received {:attempt, "127.0.0.1", 1}
    end

    test "don't retry turbopuffer's client errors" do
      client = Client.new(api_key: "not-a-real-key", retry_delay: 1)

      assert {:error, {:http_error, 401, _}} = Turbopuffer.list_namespaces(client)

      assert_received {:attempt, "gcp-us-central1.turbopuffer.com", _}
      refute_received {:attempt, "gcp-us-central1.turbopuffer.com", _}
    end
  end
end
