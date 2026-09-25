defmodule Turbopuffer.RetryTest do
  use ExUnit.Case

  alias Turbopuffer.{Client, Retry}

  def report_attempt(_event, _measurements, _metadata, test_pid), do: send(test_pid, :attempt)

  describe "retry?/1" do
    test "retries rate limits, server errors, and connection errors" do
      for status <- [408, 429, 500, 502, 503, 504] do
        assert Retry.retry?({:ok, %Finch.Response{status: status}})
      end

      assert Retry.retry?({:error, %Mint.TransportError{reason: :econnrefused}})
    end

    test "doesn't retry successes or client errors" do
      for status <- [200, 400, 401, 404, 422] do
        refute Retry.retry?({:ok, %Finch.Response{status: status}})
      end
    end
  end

  describe "delay/3" do
    test "backs off exponentially with jitter" do
      for attempt <- 0..3 do
        delay = Retry.delay({:error, %Mint.TransportError{reason: :closed}}, attempt, 100)
        assert delay >= 100 * Integer.pow(2, attempt)
        assert delay <= 100 * Integer.pow(2, attempt) + 100
      end
    end

    test "follows retry-after, capped at 30 seconds" do
      response = fn value ->
        {:ok, %Finch.Response{status: 429, headers: [{"retry-after", value}]}}
      end

      assert Retry.delay(response.("2"), 0, 100) == 2_000
      assert Retry.delay(response.("3600"), 0, 100) == 30_000
      assert Retry.delay(response.("soon"), 0, 100) in 100..200
    end
  end

  describe "requests" do
    setup do
      bypass = Bypass.open()

      client =
        Client.new(
          api_key: "test-key",
          base_url: "http://localhost:#{bypass.port}",
          retry_delay: 1
        )

      {:ok, bypass: bypass, client: client}
    end

    test "retry a rate limit until turbopuffer accepts the request", %{
      bypass: bypass,
      client: client
    } do
      {:ok, attempts} = Agent.start_link(fn -> 0 end)

      Bypass.expect(bypass, "GET", "/v1/namespaces", fn conn ->
        case Agent.get_and_update(attempts, &{&1 + 1, &1 + 1}) do
          1 -> conn |> Plug.Conn.put_resp_header("retry-after", "0") |> Plug.Conn.resp(429, "{}")
          _ -> Plug.Conn.resp(conn, 200, ~s({"namespaces": [{"id": "ns"}]}))
        end
      end)

      assert {:ok, %{namespaces: [%{"id" => "ns"}]}} = Turbopuffer.list_namespaces(client)
      assert Agent.get(attempts, & &1) == 2
    end

    test "stop after :max_retries", %{bypass: bypass} do
      client =
        Client.new(
          api_key: "test-key",
          base_url: "http://localhost:#{bypass.port}",
          max_retries: 2,
          retry_delay: 1
        )

      {:ok, attempts} = Agent.start_link(fn -> 0 end)

      Bypass.expect(bypass, "GET", "/v1/namespaces", fn conn ->
        Agent.update(attempts, &(&1 + 1))
        Plug.Conn.resp(conn, 503, "{}")
      end)

      assert {:error, {:http_error, 503, %{}}} = Turbopuffer.list_namespaces(client)
      assert Agent.get(attempts, & &1) == 3
    end

    test "don't retry client errors", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "GET", "/v1/namespaces", fn conn ->
        Plug.Conn.resp(conn, 401, ~s({"status": "error"}))
      end)

      assert {:error, {:http_error, 401, %{"status" => "error"}}} =
               Turbopuffer.list_namespaces(client)
    end

    test "retry connection errors", %{bypass: bypass, client: client} do
      Bypass.down(bypass)

      handler = "retry-test-#{System.unique_integer([:positive])}"
      :telemetry.attach(handler, [:finch, :request, :start], &__MODULE__.report_attempt/4, self())

      on_exit(fn -> :telemetry.detach(handler) end)

      # Finch returns Mint.TransportError before 0.22 and Finch.TransportError from 0.22 on.
      assert {:error, %{reason: :econnrefused}} = Turbopuffer.list_namespaces(client)

      for _ <- 1..4, do: assert_received(:attempt)
      refute_received :attempt
    end
  end
end
