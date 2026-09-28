defmodule Turbopuffer do
  @moduledoc """
  Elixir client library for the Turbopuffer vector database API.

  Turbopuffer is a vector database designed for efficient retrieval and search
  operations, supporting both vector similarity search and full-text search.

  ## Quick Start

      # Create a client
      client = Turbopuffer.new(api_key: "your-api-key")

      # Create a namespace reference
      namespace = Turbopuffer.namespace(client, "my-namespace")

      # Write vectors
      {:ok, _} = Turbopuffer.write(namespace,
        upsert_rows: [
          %{
            id: 1,
            vector: [0.1, 0.2, 0.3],
            attributes: %{
              "text" => "Sample document",
              "category" => "example"
            }
          }
        ]
      )

      # Query vectors
      {:ok, results} = Turbopuffer.query(namespace,
        vector: [0.1, 0.2, 0.3],
        top_k: 10
      )

      # Hybrid search
      {:ok, results} = Turbopuffer.hybrid_search(namespace,
        vector: [0.1, 0.2, 0.3],
        text_query: "machine learning",
        text_attribute: "text"
      )
  """

  alias Turbopuffer.{Client, Namespace, Vector, Search, Result}

  # Client options
  @type client_opts :: [
          {:api_key, String.t()}
          | {:region, atom() | String.t()}
          | {:base_url, String.t()}
          | {:finch_name, atom()}
          | {:max_retries, non_neg_integer()}
          | {:retry_delay, non_neg_integer()}
        ]

  # See Turbopuffer.Client.request/5
  @type request_opts :: [
          {:respond_async, boolean()}
          | {:pool_timeout, timeout()}
          | {:receive_timeout, timeout()}
          | {:request_timeout, timeout()}
        ]

  # A map matches documents whose attributes equal every value in it, e.g. %{"category" => "sports"}.
  # For anything else, pass turbopuffer's own filter (https://turbopuffer.com/docs/query#filtering-parameters),
  # e.g. ["And", [["price", "Gte", 10], ["status", "In", ["active", "pending"]]]].
  @type filter_value :: String.t() | number() | boolean() | nil | [String.t() | number()]
  @type filters :: %{(String.t() | atom()) => filter_value} | list()

  # Schema types for namespace configuration
  @type schema_field :: %{
          optional(String.t()) => String.t() | boolean() | map()
        }
  @type schema :: %{String.t() => schema_field()}

  # Response types
  @type query_response :: [Result.t()]
  @type success_response :: %{} | %{String.t() => any()}

  # Vector write options
  @type vector_write_opts :: [
          {:upsert_rows, [map()]}
          | {:upsert_columns, map()}
          | {:patch_rows, [map()]}
          | {:patch_columns, map()}
          | {:deletes, [String.t() | integer()]}
          | {:distance_metric, String.t()}
          | {:schema, schema()}
          | {:upsert_condition, map()}
          | {:patch_condition, map()}
          | {:delete_condition, map()}
          | {:delete_by_filter, map()}
          | {:copy_from_namespace, String.t() | map()}
          | {:encryption, map()}
          | {:patch_by_filter, map()}
          | {:patch_by_filter_allow_partial, boolean()}
          | {:delete_by_filter_allow_partial, boolean()}
          | {:return_affected_ids, boolean()}
          | {:branch_from_namespace, String.t()}
          | {:sharding, map()}
          | {:disable_backpressure, boolean()}
        ]

  @type ann_query :: [float()] | {:embed, String.t()} | {:embed, String.t(), String.t()}

  @type vector_query_opts :: [
          {:vector, ann_query()}
          | {:vector_attribute, String.t()}
          | {:top_k, pos_integer()}
          | {:include_attributes, boolean() | [String.t()]}
          | {:include_vectors, boolean()}
          | {:exclude_attributes, [String.t()]}
          | {:filters, filters()}
          | {:vector_encoding, :float | :base64}
          | {:consistency, :strong | :eventual}
        ]

  @type aggregate_opts :: [
          {:aggregate_by, %{String.t() => list()}}
          | {:group_by, [String.t()]}
          | {:top_k, pos_integer()}
          | {:filters, filters()}
          | {:consistency, :strong | :eventual}
        ]

  # Search options
  @type text_search_opts :: [
          {:query, String.t()}
          | {:attribute, String.t()}
          | {:top_k, pos_integer()}
          | {:include_attributes, boolean() | [String.t()]}
          | {:filters, filters()}
        ]

  @type hybrid_search_opts :: [
          {:vector, ann_query()}
          | {:vector_attribute, String.t()}
          | {:text_query, String.t()}
          | {:text_attribute, String.t()}
          | {:top_k, pos_integer()}
          | {:include_attributes, boolean() | [String.t()]}
          | {:filters, filters()}
          | {:rerank_by, rerank_by() | nil}
        ]

  @type rerank_by ::
          :rrf | {:rrf, [{:rank_constant, pos_integer()} | {:weights, [number()]}]}

  @type multi_query_opts :: [
          {:queries, [map()]}
          | {:top_k, pos_integer()}
          | {:include_attributes, boolean() | [String.t()]}
          | {:rerank_by, rerank_by()}
        ]

  @doc """
  Creates a new Turbopuffer client.

  ## Options
    * `:api_key` - The API key for authentication (can also use TURBOPUFFER_API_KEY env var)
    * `:region` - Any turbopuffer region, e.g. `"aws-us-east-1"` or `:aws_us_east_1` (defaults to :gcp_us_central1)
    * `:base_url` - Override the base URL for the API

  ## Examples

      client = Turbopuffer.new(api_key: "your-key")

      # With specific region
      client = Turbopuffer.new(
        api_key: "your-key",
        region: :gcp_europe_west4
      )
  """
  @spec new(client_opts()) :: Client.t()
  defdelegate new(opts), to: Client

  @doc """
  Creates a namespace reference.

  ## Examples

      namespace = Turbopuffer.namespace(client, "my-namespace")
  """
  @spec namespace(Client.t(), String.t()) :: Namespace.t()
  defdelegate namespace(client, name), to: Namespace, as: :new

  @doc """
  Writes vectors to a namespace (upserts and/or deletes).

  ## Options
    * `:upsert_rows` - List of vectors to upsert
    * `:deletes` - List of IDs to delete
    * `:distance_metric` - The distance metric to use (e.g., "cosine_distance", "euclidean_squared")
    * `:schema` - Schema configuration for attributes

  `Turbopuffer.Vector.write/2` lists every option. Unknown options raise `ArgumentError`.

  ## Examples

      # Upsert and delete in one operation
      {:ok, _} = Turbopuffer.write(namespace,
        upsert_rows: [
          %{id: 1, vector: [0.1, 0.2], attributes: %{"text" => "doc"}}
        ],
        deletes: [2, 3],
        distance_metric: "cosine_distance"
      )

      # Upsert with flat attributes
      {:ok, _} = Turbopuffer.write(namespace,
        upsert_rows: [
          %{id: 4, vector: [0.3, 0.4], text: "another doc", category: "example"}
        ]
      )
  """
  @spec write(Namespace.t(), vector_write_opts()) :: {:ok, success_response()} | {:error, term()}
  defdelegate write(namespace, opts), to: Vector

  @doc """
  Queries vectors by similarity.

  ## Options
    * `:vector` - The query vector (required)
    * `:top_k` - Number of results to return (default: 10)
    * `:include_attributes` - List of attributes to include or boolean
    * `:include_vectors` - Whether to include vectors in response
    * `:exclude_attributes` - List of attributes to exclude, instead of `:include_attributes`
    * `:filters` - Metadata filters
    * `:vector_encoding` - Response format (:float or :base64)
    * `:consistency` - Read consistency (:strong or :eventual)

  `Turbopuffer.Vector.query/2` describes every option.

  ## Examples

      {:ok, results} = Turbopuffer.query(namespace,
        vector: [0.1, 0.2, 0.3],
        top_k: 10
      )
  """
  @spec query(Namespace.t(), vector_query_opts()) :: {:ok, query_response()} | {:error, term()}
  defdelegate query(namespace, opts), to: Vector

  @doc """
  Counts or sums the documents that match `:filters`, optionally for each group of documents.
  See `Turbopuffer.Search.aggregate/2`.

  ## Examples

      {:ok, %{"count" => 42}} = Turbopuffer.aggregate(namespace, aggregate_by: %{"count" => ["Count"]})
  """
  @spec aggregate(Namespace.t(), aggregate_opts()) :: {:ok, map() | [map()]} | {:error, term()}
  defdelegate aggregate(namespace, opts), to: Search

  @doc """
  Performs full-text search.

  ## Options
    * `:query` - The text query (required)
    * `:attribute` - The attribute to search in (required)
    * `:top_k` - Number of results (default: 10)

  ## Examples

      {:ok, results} = Turbopuffer.text_search(namespace,
        query: "machine learning",
        attribute: "content",
        top_k: 20
      )
  """
  @spec text_search(Namespace.t(), text_search_opts()) ::
          {:ok, query_response()} | {:error, term()}
  defdelegate text_search(namespace, opts), to: Search, as: :text

  @doc """
  Performs hybrid search combining vector and text, fused with reciprocal rank fusion.
  See `Turbopuffer.Search.hybrid/2`.

  ## Options
    * `:vector` - The query vector
    * `:text_query` - The text query
    * `:text_attribute` - The attribute for text search
    * `:top_k` - Number of results (default: 10)
    * `:rerank_by` - How to fuse the two rankings (default: `:rrf`). `nil` returns the vector rows,
      then the text rows, unfused

  ## Examples

      {:ok, results} = Turbopuffer.hybrid_search(namespace,
        vector: [0.1, 0.2, 0.3],
        text_query: "machine learning",
        text_attribute: "content",
        top_k: 20
      )
  """
  @spec hybrid_search(Namespace.t(), hybrid_search_opts()) ::
          {:ok, query_response()} | {:error, term()}
  defdelegate hybrid_search(namespace, opts), to: Search, as: :hybrid

  @doc """
  Runs several queries in one request, optionally fusing them with reciprocal rank fusion.
  See `Turbopuffer.Search.multi_query/2`.

  ## Options
    * `:queries` - List of query configurations
    * `:top_k` - Number of fused results with `:rerank_by`
    * `:rerank_by` - `:rrf`, or `{:rrf, rank_constant: 60, weights: [2, 1]}`

  ## Examples

      queries = [
        %{rank_by: [:vector, :ann, [0.1, 0.2, 0.3]], top_k: 10},
        %{rank_by: ["content", "BM25", "search terms"], top_k: 10}
      ]
      {:ok, results} = Turbopuffer.multi_query(namespace, queries: queries, rerank_by: :rrf)
  """
  @spec multi_query(Namespace.t(), multi_query_opts()) ::
          {:ok, query_response()} | {:error, term()}
  defdelegate multi_query(namespace, opts), to: Search

  @doc """
  Deletes a namespace.

  ## Examples

      {:ok, _} = Turbopuffer.delete_namespace(namespace)
  """
  @spec delete_namespace(Namespace.t()) :: {:ok, success_response()} | {:error, term()}
  defdelegate delete_namespace(namespace), to: Namespace, as: :delete

  @type list_namespaces_opts :: [
          {:prefix, String.t()}
          | {:page_size, pos_integer()}
          | {:cursor, String.t()}
        ]

  @doc """
  Lists namespaces.

  ## Options
    * `:prefix` - Filter namespaces by prefix
    * `:page_size` - Number of results per page
    * `:cursor` - Cursor for pagination

  ## Examples

      {:ok, result} = Turbopuffer.list_namespaces(client)
      {:ok, result} = Turbopuffer.list_namespaces(client, prefix: "prod-", page_size: 100)
  """
  @spec list_namespaces(Client.t(), list_namespaces_opts()) :: {:ok, map()} | {:error, term()}
  defdelegate list_namespaces(client, opts \\ []), to: Namespace, as: :list
end
