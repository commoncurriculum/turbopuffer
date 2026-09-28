defmodule Turbopuffer.Client do
  @moduledoc """
  HTTP client for the Turbopuffer API using Finch.
  """

  alias Turbopuffer.Retry

  # Elixir 1.18 ships a JSON module; older versions need Jason.
  @json_library Application.compile_env(
                  :turbopuffer,
                  :json_library,
                  if(Code.ensure_loaded?(JSON), do: JSON, else: Jason)
                )

  unless Code.ensure_loaded?(@json_library) do
    raise ArgumentError,
          "turbopuffer's JSON library #{inspect(@json_library)} is not available. " <>
            "Add {:jason, \"~> 1.4\"} to your deps, or set `config :turbopuffer, :json_library, ...`"
  end

  defstruct [:api_key, :base_url, :finch_name, max_retries: 3, retry_delay: 500]

  @type t :: %__MODULE__{
          api_key: String.t(),
          base_url: String.t(),
          finch_name: atom(),
          max_retries: non_neg_integer(),
          retry_delay: non_neg_integer()
        }

  @type response :: {:ok, map()} | {:error, term()}

  @doc """
  Creates a new Turbopuffer client.

  ## Options
    * `:api_key` - Required. The API key for authentication
    * `:region` - Optional. Any turbopuffer region, as a string (`"aws-us-east-1"`) or an atom
      (`:aws_us_east_1`). Defaults to `:gcp_us_central1`. See https://turbopuffer.com/docs/regions
    * `:base_url` - Optional. Overrides the region's URL
    * `:finch_name` - Optional. The name of the Finch pool (defaults to Turbopuffer.Finch)
    * `:max_retries` - Optional. How many times to retry a request that fails with 408, 429, or 5xx,
      or with a connection error (defaults to 3). turbopuffer returns 429 when writes outpace
      indexing. Writes are retried too: upserts, patches, and deletes are idempotent, but a conditional
      write whose first attempt succeeded unseen can be skipped on the retry
    * `:retry_delay` - Optional. Milliseconds before the first retry, doubling each time with jitter,
      unless the response sets `retry-after` (defaults to 500)
  """
  @spec new(Turbopuffer.client_opts()) :: t()
  def new(opts) do
    api_key = Keyword.get(opts, :api_key) || System.get_env("TURBOPUFFER_API_KEY")

    if is_nil(api_key) do
      raise ArgumentError,
            "API key is required. Pass :api_key option or set TURBOPUFFER_API_KEY environment variable"
    end

    base_url =
      Keyword.get_lazy(opts, :base_url, fn ->
        opts |> Keyword.get(:region, :gcp_us_central1) |> region_url()
      end)

    finch_name = Keyword.get(opts, :finch_name, Turbopuffer.Finch)

    %__MODULE__{
      api_key: api_key,
      base_url: base_url,
      finch_name: finch_name,
      max_retries: Keyword.get(opts, :max_retries, 3),
      retry_delay: Keyword.get(opts, :retry_delay, 500)
    }
  end

  defp region_url(region) when is_atom(region) do
    region |> Atom.to_string() |> String.replace("_", "-") |> region_url()
  end

  defp region_url(region) when is_binary(region) do
    if region =~ ~r/\A[a-z0-9]+(-[a-z0-9]+)+\z/ do
      "https://#{region}.turbopuffer.com"
    else
      raise ArgumentError,
            "invalid turbopuffer region #{inspect(region)}, expected a name like \"aws-us-east-1\""
    end
  end

  defp region_url(region) do
    raise ArgumentError, "invalid turbopuffer region #{inspect(region)}"
  end

  @doc """
  Makes an HTTP request to the Turbopuffer API.

  ## Options

    * `:respond_async` - Lets turbopuffer run the operation in the background, for the operations
      that can (`copy_from_namespace` and recall, see
      https://turbopuffer.com/docs/api-overview#asynchronous-requests). The request still returns the
      operation's result, polling for it until the operation finishes, as turbopuffer's own clients
      do. turbopuffer may answer straight away instead

  `request/5`, `get/3`, `post/4`, and `delete/3` pass the others to `Finch.request/3`:

    * `:pool_timeout` - Milliseconds to wait for a connection from the pool (Finch's default: 5_000)
    * `:receive_timeout` - Milliseconds to wait for each chunk of the response (Finch's default:
      15_000)
    * `:request_timeout` - Milliseconds to wait for the whole response, HTTP/1 only (Finch's
      default: `:infinity`)
  """
  @spec request(t(), atom(), String.t(), map() | nil, Turbopuffer.request_opts()) :: response()
  def request(client, method, path, body \\ nil, opts \\ []) do
    {respond_async, opts} = Keyword.pop(opts, :respond_async, false)

    headers = [
      {"authorization", "Bearer #{client.api_key}"},
      {"content-type", "application/json"},
      {"accept", "application/json"}
      | if(respond_async, do: [{"prefer", "respond-async"}], else: [])
    ]

    encoded_body = if body, do: @json_library.encode!(body), else: nil

    request = Finch.build(method, client.base_url <> path, headers, encoded_body)

    with {:ok, response} <- send_with_retries(client, request, opts, 0),
         {:ok, decoded_body} <- decode_response(response) do
      case {response.status, List.keyfind(response.headers, "location", 0)} do
        {202, {_, location}} when respond_async ->
          await(client, operation_path(location), opts, 0)

        {status, _} when status in 200..299 ->
          {:ok, decoded_body}

        {status, _} ->
          {:error, {:http_error, status, decoded_body}}
      end
    end
  end

  # turbopuffer keeps an operation's result for an hour after it finishes, so polling can back off.
  defp await(client, path, opts, attempt) do
    case request(client, :get, path, nil, opts) do
      {:ok, %{"status" => "running"}} ->
        Process.sleep(min(250 * Integer.pow(2, attempt), 5_000))
        await(client, path, opts, attempt + 1)

      {:ok, %{"status" => "finished", "result" => %{"success" => result}}} ->
        {:ok, result}

      {:ok, %{"status" => "finished", "result" => %{"error" => error}}} ->
        {:error, {:http_error, error["status_code"], error["detail"]}}

      other ->
        other
    end
  end

  defp operation_path(location) do
    %URI{path: path, query: query} = URI.parse(location)
    if query, do: path <> "?" <> query, else: path
  end

  defp send_with_retries(client, request, opts, attempt) do
    result = Finch.request(request, client.finch_name, opts)

    if attempt < client.max_retries and Retry.retry?(result) do
      Process.sleep(Retry.delay(result, attempt, client.retry_delay))
      send_with_retries(client, request, opts, attempt + 1)
    else
      result
    end
  end

  @doc """
  Makes a GET request to the Turbopuffer API.
  """
  @spec get(t(), String.t(), Turbopuffer.request_opts()) :: response()
  def get(client, path, opts \\ []), do: request(client, :get, path, nil, opts)

  @doc """
  Makes a POST request to the Turbopuffer API.
  """
  @spec post(t(), String.t(), map(), Turbopuffer.request_opts()) :: response()
  def post(client, path, body, opts \\ []), do: request(client, :post, path, body, opts)

  @doc """
  Makes a DELETE request to the Turbopuffer API.
  """
  @spec delete(t(), String.t(), Turbopuffer.request_opts()) :: response()
  def delete(client, path, opts \\ []), do: request(client, :delete, path, nil, opts)

  defp decode_response(%{body: ""}), do: {:ok, %{}}

  defp decode_response(%{body: body}) when is_binary(body) do
    case @json_library.decode(body) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, _} = error -> error
    end
  rescue
    _ -> {:error, :invalid_json}
  end
end
