defmodule Turbopuffer.RetryTest do
  use ExUnit.Case, async: true

  alias Turbopuffer.Retry

  # turbopuffer can't be made to answer 429 or 5xx, so these check the policy the retry loop follows.
  # request_test.exs runs the loop itself against a refused connection.
  describe "retry?/1" do
    test "retries rate limits, server errors, and connection errors" do
      for status <- [408, 429, 500, 502, 503, 504] do
        assert Retry.retry?({:ok, %Finch.Response{status: status}})
      end

      assert Retry.retry?({:error, %Mint.TransportError{reason: :econnrefused}})
    end

    test "doesn't retry successes or client errors" do
      for status <- [200, 202, 400, 401, 404, 422] do
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
end
