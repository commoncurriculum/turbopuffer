defmodule Turbopuffer.Client do
  @moduledoc """
  HTTP client for the Turbopuffer API using Finch.
  """

  # Elixir 1.18 ships a JSON module; older versions need Jason.
  @default_json_library if Code.ensure_loaded?(JSON), do: JSON, else: Jason

  defstruct [:api_key, :base_url, :finch_name, :json_library]

  @type t :: %__MODULE__{
          api_key: String.t(),
          base_url: String.t(),
          finch_name: atom(),
          json_library: module()
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
    * `:json_library` - Optional. A module with `encode!/1` and `decode/1`. Defaults to the
      `:json_library` application setting, then to Elixir's `JSON` on 1.18+ and `Jason` before that.
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

    json_library =
      Keyword.get_lazy(opts, :json_library, fn ->
        Application.get_env(:turbopuffer, :json_library, @default_json_library)
      end)

    unless Code.ensure_loaded?(json_library) do
      raise ArgumentError,
            "JSON library #{inspect(json_library)} is not available. " <>
              "Add {:jason, \"~> 1.4\"} to your deps or set the :json_library option"
    end

    %__MODULE__{
      api_key: api_key,
      base_url: base_url,
      finch_name: finch_name,
      json_library: json_library
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
  """
  @spec request(t(), atom(), String.t(), map() | nil, Turbopuffer.request_opts()) :: response()
  def request(client, method, path, body \\ nil, opts \\ []) do
    url = client.base_url <> path

    headers = [
      {"authorization", "Bearer #{client.api_key}"},
      {"content-type", "application/json"},
      {"accept", "application/json"}
    ]

    encoded_body = if body, do: client.json_library.encode!(body), else: nil

    request = Finch.build(method, url, headers, encoded_body)

    with {:ok, response} <- Finch.request(request, client.finch_name, opts),
         {:ok, decoded_body} <- decode_response(response, client.json_library) do
      if response.status in 200..299 do
        {:ok, decoded_body}
      else
        {:error, {:http_error, response.status, decoded_body}}
      end
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

  defp decode_response(%{body: ""}, _json_library), do: {:ok, %{}}

  defp decode_response(%{body: body}, json_library) when is_binary(body) do
    case json_library.decode(body) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, _} = error -> error
    end
  rescue
    _ -> {:error, :invalid_json}
  end
end
