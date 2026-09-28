defmodule Turbopuffer.Namespace do
  @moduledoc """
  Handles namespace operations for Turbopuffer.
  """

  alias Turbopuffer.Client

  defstruct [:client, :name]

  @type t :: %__MODULE__{
          client: Client.t(),
          name: String.t()
        }

  @doc """
  Creates a namespace reference.
  """
  @spec new(Client.t(), String.t()) :: t()
  def new(client, name) do
    %__MODULE__{
      client: client,
      name: name
    }
  end

  @doc """
  Deletes a namespace.

  ## Examples

      {:ok, _} = Turbopuffer.Namespace.delete(namespace)
  """
  @spec delete(t()) :: {:ok, map()} | {:error, term()}
  def delete(%__MODULE__{} = namespace) do
    path = "/v2/namespaces/#{namespace.name}"
    Client.delete(namespace.client, path)
  end

  @doc """
  Lists namespaces.

  Returns one page of namespaces, as maps with `"id"`, and the `next_cursor` for the next page, which
  is `nil` on the last page.

  ## Options
    * `:prefix` - Filter namespaces by prefix
    * `:page_size` - Number of results per page (turbopuffer's default: 100, maximum: 1,000)
    * `:cursor` - Cursor for pagination

  Unknown options raise `ArgumentError`.

  ## Examples

      {:ok, result} = Turbopuffer.Namespace.list(client)
      {:ok, result} = Turbopuffer.Namespace.list(client, prefix: "prod-", page_size: 100)
  """
  @spec list(Client.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def list(client, opts \\ []) do
    query_params =
      opts
      |> Keyword.validate!([:prefix, :page_size, :cursor])
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)

    query_string = URI.encode_query(query_params)
    path = if query_string == "", do: "/v1/namespaces", else: "/v1/namespaces?#{query_string}"

    case Client.get(client, path) do
      {:ok, %{"namespaces" => namespaces} = response} ->
        next_cursor = Map.get(response, "next_cursor")
        {:ok, %{namespaces: namespaces, next_cursor: next_cursor}}

      {:ok, _response} ->
        {:ok, %{namespaces: [], next_cursor: nil}}

      error ->
        error
    end
  end
end
