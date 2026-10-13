defmodule Turbopuffer.Namespace do
  @moduledoc """
  Handles namespace operations for Turbopuffer.
  """

  alias Turbopuffer.{Client, Query}

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
  Returns a namespace's metadata (https://turbopuffer.com/docs/metadata): its `"schema"`,
  `"approx_row_count"`, `"approx_logical_bytes"`, `"index"` status, and `"read_only"`,
  `"sharding"`, `"pinning"`, and `"branching"` when they're set.

  ## Examples

      {:ok, %{"approx_row_count" => count}} = Turbopuffer.Namespace.metadata(namespace)
  """
  @spec metadata(t()) :: {:ok, map()} | {:error, term()}
  def metadata(%__MODULE__{} = namespace) do
    Client.get(namespace.client, "/v1/namespaces/#{namespace.name}/metadata")
  end

  @doc """
  Changes a namespace's metadata and returns the updated metadata.

  ## Options
    * `:read_only` - `true` rejects document and schema writes until it's `false` again
    * `:pinning` - `%{replicas: n}` or `true` reserves compute for the namespace, billed by the
      hour, and `nil` releases it (https://turbopuffer.com/docs/pinning)

  Unknown options raise `ArgumentError`.

  ## Examples

      {:ok, %{"read_only" => true}} = Turbopuffer.Namespace.update_metadata(namespace, read_only: true)
  """
  @spec update_metadata(t(), keyword()) :: {:ok, map()} | {:error, term()}
  def update_metadata(%__MODULE__{} = namespace, changes) do
    body =
      changes
      |> Keyword.validate!([:read_only, :pinning])
      |> Map.new(fn {key, value} -> {Atom.to_string(key), value} end)

    Client.patch(namespace.client, "/v1/namespaces/#{namespace.name}/metadata", body)
  end

  @doc """
  Tells turbopuffer that latency-sensitive queries to a namespace are coming, so it can warm its
  cache (https://turbopuffer.com/docs/warm-cache).

  ## Examples

      {:ok, _} = Turbopuffer.Namespace.warm_cache(namespace)
  """
  @spec warm_cache(t()) :: {:ok, map()} | {:error, term()}
  def warm_cache(%__MODULE__{} = namespace) do
    Client.get(namespace.client, "/v1/namespaces/#{namespace.name}/hint_cache_warm")
  end

  @doc """
  Measures the recall of a namespace's vector index (https://turbopuffer.com/docs/recall),
  returning `"avg_recall"`, `"avg_ann_count"`, and `"avg_exhaustive_count"`. turbopuffer may run it
  in the background; this waits for the result.

  ## Options
    * `:num` - The number of random documents whose vectors to search for (turbopuffer's
      default: 25)
    * `:top_k` - The number of results each search compares (turbopuffer's default: 10)
    * `:filters` - Metadata filters for each search to keep to, as `Turbopuffer.query/2` takes them
    * `:rank_by` - One `["attribute", "ANN", vector]` search to measure instead of random
      documents' vectors. turbopuffer only takes it with `:num` 1 or none, and answers 404 for about
      10 seconds after the namespace is created

  Unknown options raise `ArgumentError`.

  ## Examples

      {:ok, %{"avg_recall" => recall}} = Turbopuffer.Namespace.recall(namespace, num: 5, top_k: 10)
  """
  @spec recall(t(), keyword()) :: {:ok, map()} | {:error, term()}
  def recall(%__MODULE__{} = namespace, opts \\ []) do
    body =
      opts
      |> Keyword.validate!([:num, :top_k, :filters, :rank_by])
      |> Keyword.delete(:filters)
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new(fn {key, value} -> {Atom.to_string(key), value} end)
      |> Query.put_filters(opts[:filters])

    Client.post(namespace.client, "/v1/namespaces/#{namespace.name}/_debug/recall", body,
      respond_async: true
    )
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
