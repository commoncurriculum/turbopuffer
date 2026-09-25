defmodule Turbopuffer.Search do
  @moduledoc """
  Handles text and hybrid search operations for Turbopuffer.
  """

  alias Turbopuffer.{Client, Namespace, Result}

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
    query = Keyword.fetch!(opts, :query)
    attribute = Keyword.fetch!(opts, :attribute)
    path = "/v2/namespaces/#{namespace.name}/query"

    body = build_text_search_body(opts, query, attribute)

    namespace.client
    |> Client.post(path, body)
    |> handle_search_response()
  end

  defp build_text_search_body(opts, query, attribute) do
    base_body = %{
      "rank_by" => [attribute, "BM25", query],
      "top_k" => Keyword.get(opts, :top_k, 10),
      "include_attributes" => normalize_include_attributes(Keyword.get(opts, :include_attributes, true))
    }

    case Keyword.get(opts, :filters) do
      nil -> base_body
      filters -> Map.put(base_body, "filters", format_filters(filters))
    end
  end

  # Handle different response formats with pattern matching
  defp handle_search_response({:ok, %{"rows" => rows}}) when is_list(rows) do
    {:ok, Result.from_maps(rows)}
  end

  defp handle_search_response({:ok, %{"vectors" => vectors}}) when is_list(vectors) do
    {:ok, Result.from_maps(vectors)}
  end

  defp handle_search_response({:ok, %{"data" => data}}) when is_list(data) do
    {:ok, Result.from_maps(data)}
  end

  defp handle_search_response({:ok, _}) do
    {:ok, []}
  end

  defp handle_search_response(error), do: error

  @doc """
  Performs a hybrid search combining vector and text search.

  ## Options
    * `:vector` - The query vector (required)
    * `:text_query` - The text query string (required)
    * `:text_attribute` - The attribute to search text in (required)
    * `:top_k` - Number of results to return (default: 10)
    * `:include_attributes` - List of attributes to include (default: true)
    * `:filters` - Metadata filters to apply
    * `:rerank_by` - `:rrf` to fuse the two rankings, see `multi_query/2`

  ## Examples

      Turbopuffer.Search.hybrid(namespace,
        vector: [0.1, 0.2, 0.3],
        text_query: "machine learning",
        text_attribute: "content",
        top_k: 20,
        filters: %{"category" => "tutorial"}
      )
  """
  @spec hybrid(Namespace.t(), Turbopuffer.hybrid_search_opts()) ::
          {:ok, Turbopuffer.query_response()} | {:error, term()}
  def hybrid(%Namespace{} = namespace, opts) do
    vector = Keyword.fetch!(opts, :vector)
    text_query = Keyword.fetch!(opts, :text_query)
    text_attribute = Keyword.fetch!(opts, :text_attribute)
    top_k = Keyword.get(opts, :top_k, 10)
    include_attributes = Keyword.get(opts, :include_attributes, true)
    filters = Keyword.get(opts, :filters)

    # Use multi_query for hybrid search
    queries = [
      %{
        rank_by: ["vector", "ANN", vector],
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
      rerank_by: Keyword.get(opts, :rerank_by)
    )
  end

  @doc """
  Runs several queries in one request.

  Without `:rerank_by`, returns the queries' rows one query after another, with duplicate ids
  removed, and each query's own `top_k` applies. With `rerank_by: :rrf`, turbopuffer fuses the
  rankings with reciprocal rank fusion (https://turbopuffer.com/docs/query#reciprocal-rank-fusion),
  `:top_k` limits the fused list, and each row's `dist` is its RRF score.

  ## Options
    * `:queries` - List of query configurations
    * `:top_k` - Number of fused results to return with `:rerank_by` (default: 10)
    * `:include_attributes` - Attributes to include in results
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

      {:ok, %{"rows" => rows}} when is_list(rows) ->
        {:ok, Result.from_maps(rows)}

      {:ok, %{"vectors" => vectors}} when is_list(vectors) ->
        {:ok, Result.from_maps(vectors)}

      {:ok, _response} ->
        {:ok, []}

      error ->
        error
    end
  end

  defp rerank_by(nil), do: nil
  defp rerank_by(:rrf), do: ["RRF"]

  defp rerank_by({:rrf, params}) when is_list(params) do
    params = Keyword.validate!(params, [:rank_constant, :weights])
    ["RRF", Map.new(params, fn {key, value} -> {Atom.to_string(key), value} end)]
  end

  defp rerank_by(other) do
    raise ArgumentError, "invalid :rerank_by #{inspect(other)}, expected :rrf or {:rrf, keyword}"
  end

  defp format_query(%{rank_by: rank_by} = query, include_attributes) do
    base_query = %{
      "rank_by" => format_rank_by(rank_by),
      "top_k" => Map.get(query, :top_k, 10),
      "include_attributes" => normalize_include_attributes(Map.get(query, :include_attributes, include_attributes))
    }

    case Map.get(query, :filters) do
      nil -> base_query
      filters -> Map.put(base_query, "filters", format_filters(filters))
    end
  end

  # Pattern match on rank_by formats
  defp format_rank_by([:vector, :ann, vector]) do
    ["vector", "ANN", vector]
  end

  defp format_rank_by([attribute, "BM25", text]) when is_binary(attribute) do
    [attribute, "BM25", text]
  end

  defp format_rank_by([attribute, method, value]) do
    [to_string(attribute), to_string(method), value]
  end

  defp format_rank_by(rank_by), do: rank_by

  defp normalize_include_attributes(:all), do: true
  defp normalize_include_attributes(value) when is_boolean(value), do: value
  defp normalize_include_attributes(value) when is_list(value), do: value
  defp normalize_include_attributes(value) do
    raise ArgumentError,
      "invalid value for :include_attributes: #{inspect(value)}. " <>
      "Expected a boolean, :all, or a list of attribute name strings"
  end

  # Convert map filters to tuple format expected by API
  defp format_filters(nil), do: nil

  defp format_filters(filters) when is_map(filters) do
    conditions =
      Enum.map(filters, fn {key, value} ->
        [to_string(key), "Eq", value]
      end)

    case conditions do
      [single] -> single
      multiple -> ["And" | [multiple]]
    end
  end

  defp format_filters(filters), do: filters
end
