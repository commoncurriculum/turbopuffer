defmodule Turbopuffer.Search do
  @moduledoc """
  Handles text and hybrid search operations for Turbopuffer.
  """

  alias Turbopuffer.{Client, Namespace, Query, RankBy, Result}

  @text_options [:query, :attribute, :top_k, :include_attributes, :filters]
  @hybrid_options [
    :vector,
    :vector_attribute,
    :text_query,
    :text_attribute,
    :top_k,
    :include_attributes,
    :filters,
    :rerank_by
  ]
  @multi_query_options [:queries, :top_k, :include_attributes, :rerank_by]
  @query_keys [:rank_by, :top_k, :include_attributes, :filters]
  @aggregate_options [:aggregate_by, :group_by, :top_k, :filters, :consistency]

  @doc """
  Performs a full-text search using BM25 ranking.

  ## Options
    * `:query` - The text query string (required)
    * `:attribute` - The attribute to search in (required)
    * `:top_k` - Number of results to return (default: 10)
    * `:include_attributes` - List of attributes to include in results
    * `:filters` - Additional metadata filters

  ## Examples

      Turbopuffer.Search.text(namespace,
        query: "machine learning",
        attribute: "content",
        top_k: 20
      )
  """
  @spec text(Namespace.t(), Turbopuffer.text_search_opts()) ::
          {:ok, Turbopuffer.query_response()} | {:error, term()}
  def text(%Namespace{} = namespace, opts) do
    Keyword.validate!(opts, @text_options)
    query = Keyword.fetch!(opts, :query)
    attribute = Keyword.fetch!(opts, :attribute)

    body =
      Query.put_filters(
        %{
          "rank_by" => [attribute, "BM25", query],
          "top_k" => Keyword.get(opts, :top_k, 10),
          "include_attributes" =>
            Query.normalize_include_attributes(Keyword.get(opts, :include_attributes, true))
        },
        opts[:filters]
      )

    namespace.client
    |> Client.post("/v2/namespaces/#{namespace.name}/query", body)
    |> Query.results()
  end

  @doc """
  Performs a hybrid search combining vector and text search.

  turbopuffer fuses the vector and BM25 rankings with reciprocal rank fusion, so the results are
  one ranking of at most `:top_k` rows, and each row's `dist` is its RRF score.

  ## Options
    * `:vector` - The query vector (required). Pass `{:embed, text}` or `{:embed, text, model}` to have
      turbopuffer embed the text (https://turbopuffer.com/docs/embedding)
    * `:vector_attribute` - The attribute to search by vector (default: "vector"). For native
      embedding, the string attribute that has `embed` in the schema
    * `:text_query` - The text query string (required)
    * `:text_attribute` - The attribute to search text in (required)
    * `:top_k` - Number of results to return (default: 10)
    * `:include_attributes` - List of attributes to include (default: true)
    * `:filters` - Metadata filters to apply
    * `:rerank_by` - How to fuse the two rankings (default: `:rrf`), see `multi_query/2`. `nil`
      returns up to `:top_k` vector rows followed by up to `:top_k` BM25 rows, with duplicate ids
      removed

  ## Examples

      Turbopuffer.Search.hybrid(namespace,
        vector: [0.1, 0.2, 0.3],
        text_query: "machine learning",
        text_attribute: "content",
        top_k: 20,
        filters: %{"category" => "tutorial"}
      )

      # Let turbopuffer embed the query for an attribute it embeds natively
      Turbopuffer.Search.hybrid(namespace,
        vector: {:embed, "machine learning"},
        vector_attribute: "content",
        text_query: "machine learning",
        text_attribute: "content"
      )
  """
  @spec hybrid(Namespace.t(), Turbopuffer.hybrid_search_opts()) ::
          {:ok, Turbopuffer.query_response()} | {:error, term()}
  def hybrid(%Namespace{} = namespace, opts) do
    Keyword.validate!(opts, @hybrid_options)
    vector = Keyword.fetch!(opts, :vector)
    vector_attribute = Keyword.get(opts, :vector_attribute, "vector")
    text_query = Keyword.fetch!(opts, :text_query)
    text_attribute = Keyword.fetch!(opts, :text_attribute)
    top_k = Keyword.get(opts, :top_k, 10)
    include_attributes = Keyword.get(opts, :include_attributes, true)
    filters = Keyword.get(opts, :filters)

    queries = [
      %{
        rank_by: RankBy.ann(vector_attribute, vector),
        top_k: top_k,
        include_attributes: include_attributes,
        filters: filters
      },
      %{
        rank_by: [text_attribute, "BM25", text_query],
        top_k: top_k,
        include_attributes: include_attributes,
        filters: filters
      }
    ]

    multi_query(namespace,
      queries: queries,
      top_k: top_k,
      rerank_by: Keyword.get(opts, :rerank_by, :rrf)
    )
  end

  @doc """
  Runs several queries in one request.

  Without `:rerank_by`, returns the queries' rows one query after another, with duplicate ids
  removed, and each query's own `top_k` applies. With `rerank_by: :rrf`, turbopuffer fuses the
  rankings with reciprocal rank fusion (https://turbopuffer.com/docs/query#reciprocal-rank-fusion),
  `:top_k` limits the fused list, and each row's `dist` is its RRF score.

  ## Options
    * `:queries` - Up to 16 queries, each a map with `:rank_by` and optionally `:top_k`
      (default: 10), `:include_attributes`, and `:filters`. Other keys raise `ArgumentError`
    * `:top_k` - Number of fused results to return with `:rerank_by` (default: 10)
    * `:include_attributes` - Attributes to include in results, for queries that don't set their own
    * `:rerank_by` - `:rrf`, or `{:rrf, rank_constant: 60, weights: [2, 1]}` with one weight per query

  ## Examples

      queries = [
        %{rank_by: ["vector", "ANN", [0.1, 0.2, 0.3]], top_k: 10},
        %{rank_by: ["content", "BM25", "search terms"], top_k: 10}
      ]

      Turbopuffer.Search.multi_query(namespace,
        queries: queries,
        top_k: 20
      )

      # Fuse the two rankings, weighting the vector search twice as heavily
      Turbopuffer.Search.multi_query(namespace,
        queries: queries,
        top_k: 20,
        rerank_by: {:rrf, weights: [2, 1]}
      )
  """
  @spec multi_query(Namespace.t(), Turbopuffer.multi_query_opts()) ::
          {:ok, Turbopuffer.query_response()} | {:error, term()}
  def multi_query(%Namespace{} = namespace, opts) do
    Keyword.validate!(opts, @multi_query_options)
    queries = Keyword.fetch!(opts, :queries)
    top_k = Keyword.get(opts, :top_k, 10)
    include_attributes = Keyword.get(opts, :include_attributes, true)

    path = "/v2/namespaces/#{namespace.name}/query?stainless_overload=multiQuery"

    formatted_queries =
      Enum.map(queries, fn query ->
        format_query(query, include_attributes)
      end)

    # turbopuffer ignores a top-level top_k, so each query's own top_k applies. A top-level limit
    # caps the fused list that rerank_by returns.
    body =
      case rerank_by(Keyword.get(opts, :rerank_by)) do
        nil -> %{"queries" => formatted_queries}
        rerank_by -> %{"queries" => formatted_queries, "rerank_by" => rerank_by, "limit" => top_k}
      end

    case Client.post(namespace.client, path, body) do
      {:ok, %{"results" => results}} when is_list(results) ->
        # One result per query, or a single fused result with rerank_by
        all_rows =
          results
          |> Enum.flat_map(fn %{"rows" => rows} -> rows || [] end)
          |> Enum.uniq_by(&Map.get(&1, "id"))

        {:ok, Result.from_maps(all_rows)}

      response ->
        Query.results(response)
    end
  end

  @doc """
  Aggregates the documents that match `:filters`, or every document in the namespace.

  Returns a map from each aggregation's label to its value, or with `:group_by`, a list with a map
  for each group: its `:group_by` attributes and aggregations, ordered by the `:group_by` attributes.

  ## Options
    * `:aggregate_by` - A map from labels to aggregate functions (required): `["Count"]`, or
      `["Sum", attribute]` for an int, uint, or float attribute. Up to 8
    * `:group_by` - Attributes to group the documents by, aggregating each group
    * `:top_k` - The number of groups to return, up to 10,000
    * `:filters` - Metadata filters to apply
    * `:consistency` - `:strong` (the default) or `:eventual`

  ## Examples

      {:ok, %{"count" => 42, "total" => 128}} =
        Turbopuffer.Search.aggregate(namespace,
          aggregate_by: %{"count" => ["Count"], "total" => ["Sum", "price"]}
        )

      {:ok, [%{"category" => "news", "count" => 2}, %{"category" => "sports", "count" => 5}]} =
        Turbopuffer.Search.aggregate(namespace,
          aggregate_by: %{"count" => ["Count"]},
          group_by: ["category"]
        )
  """
  @spec aggregate(Namespace.t(), Turbopuffer.aggregate_opts()) ::
          {:ok, map() | [map()]} | {:error, term()}
  def aggregate(%Namespace{} = namespace, opts) do
    Keyword.validate!(opts, @aggregate_options)

    body =
      %{"aggregate_by" => Keyword.fetch!(opts, :aggregate_by)}
      |> put("group_by", opts[:group_by])
      |> put("top_k", opts[:top_k])
      |> Query.put_filters(opts[:filters])
      |> Query.put_consistency(opts[:consistency])

    case Client.post(namespace.client, "/v2/namespaces/#{namespace.name}/query", body) do
      {:ok, %{"aggregation_groups" => groups}} -> {:ok, groups}
      {:ok, %{"aggregations" => aggregations}} -> {:ok, aggregations}
      other -> other
    end
  end

  defp put(body, _key, nil), do: body
  defp put(body, key, value), do: Map.put(body, key, value)

  defp rerank_by(nil), do: nil
  defp rerank_by(:rrf), do: ["RRF"]

  defp rerank_by({:rrf, params}) when is_list(params) do
    params = Keyword.validate!(params, [:rank_constant, :weights])
    ["RRF", Map.new(params, fn {key, value} -> {Atom.to_string(key), value} end)]
  end

  defp rerank_by(other) do
    raise ArgumentError, "invalid :rerank_by #{inspect(other)}, expected :rrf or {:rrf, keyword}"
  end

  defp format_query(query, include_attributes) when is_map(query) do
    case Map.keys(query) -- @query_keys do
      [] ->
        Query.put_filters(
          %{
            "rank_by" => format_rank_by(Map.fetch!(query, :rank_by)),
            "top_k" => Map.get(query, :top_k, 10),
            "include_attributes" =>
              Query.normalize_include_attributes(
                Map.get(query, :include_attributes, include_attributes)
              )
          },
          query[:filters]
        )

      unknown ->
        raise ArgumentError,
              "unknown keys #{inspect(unknown)} in query #{inspect(query)}, " <>
                "expected #{inspect(@query_keys)}"
    end
  end

  # Pattern match on rank_by formats
  defp format_rank_by([:vector, :ann, vector]) do
    ["vector", "ANN", vector]
  end

  defp format_rank_by([attribute, method, value]) do
    [to_string(attribute), to_string(method), value]
  end

  defp format_rank_by(rank_by), do: rank_by
end
