defmodule Turbopuffer.Retry do
  @moduledoc false

  @statuses [408, 429, 500, 502, 503, 504]
  @max_delay 30_000

  # Finch 0.22 started wrapping Mint's transport errors in its own struct.
  @transport_errors [Mint.TransportError, Finch.TransportError]

  @spec retry?(term()) :: boolean()
  def retry?({:ok, %Finch.Response{status: status}}), do: status in @statuses
  def retry?({:error, %error{}}) when error in @transport_errors, do: true
  def retry?(_result), do: false

  @spec delay(term(), non_neg_integer(), non_neg_integer()) :: non_neg_integer()
  def delay(result, attempt, base) do
    case retry_after(result) do
      nil -> min(base * Integer.pow(2, attempt) + :rand.uniform(base + 1) - 1, @max_delay)
      seconds -> min(seconds * 1000, @max_delay)
    end
  end

  defp retry_after({:ok, %Finch.Response{headers: headers}}) do
    with {_, value} <- List.keyfind(headers, "retry-after", 0),
         {seconds, ""} <- Integer.parse(value) do
      seconds
    else
      _ -> nil
    end
  end

  defp retry_after(_result), do: nil
end
