defmodule Turbopuffer.Vector do
  @moduledoc """
  Handles vector operations for Turbopuffer.
  """

  alias Turbopuffer.{Client, Namespace, Query, RankBy}

  @write_options [
    :upsert_rows,
    :upsert_columns,
    :patch_rows,
    :patch_columns,
    :deletes,
    :delete_by_filter,
    :distance_metric,
    :schema,
    :upsert_condition,
    :patch_condition,
    :delete_condition,
    :copy_from_namespace,
    :encryption,
    :patch_by_filter,
    :patch_by_filter_allow_partial,
    :delete_by_filter_allow_partial,
    :return_affected_ids,
    :branch_from_namespace,
    :sharding,
    :disable_backpressure
  ]

  @query_options [
    :vector,
    :vector_attribute,
    :top_k,
    :include_attributes,
    :include_vectors,
    :exclude_attributes,
    :filters,
    :vector_encoding,
    :consistency
  ]

  @doc """
  Writes vectors to a namespace (upserts, patches, and/or deletes).

  ## Options
    * `:upsert_rows` - List of vectors to upsert
    * `:upsert_columns` - Column-based vector upsert
    * `:patch_rows` - List of partial updates
    * `:patch_columns` - Column-based partial updates
    * `:deletes` - List of IDs to delete
    * `:delete_by_filter` - Delete documents matching filter
    * `:distance_metric` - The distance metric to use (e.g., "cosine_distance", "euclidean_squared")
    * `:schema` - Schema configuration for attributes
    * `:upsert_condition` - Conditional upsert based on existing state
    * `:patch_condition` - Conditional patch
    * `:delete_condition` - Conditional delete
    * `:copy_from_namespace` - Copy all documents from another namespace, given by name or as
      `%{source_namespace: ..., source_region: ..., source_api_key: ...}`. Waits for the copy to
      finish, which turbopuffer may run in the background
    * `:encryption` - Customer managed encryption configuration
    * `:patch_by_filter` - `%{filters: ..., patch: ...}` to patch every document matching a filter
    * `:patch_by_filter_allow_partial`, `:delete_by_filter_allow_partial` - Let filter writes stop at
      turbopuffer's per-request limit instead of failing
    * `:return_affected_ids` - Return the ids that were upserted, patched, and deleted
    * `:branch_from_namespace` - Branch from another namespace
    * `:sharding` - Sharding configuration
    * `:disable_backpressure` - Accept writes past the unindexed-data limit

  Unknown options raise `ArgumentError`.

  ## Examples

      # Upsert vectors with nested attributes
      Turbopuffer.Vector.write(namespace,
        upsert_rows: [
          %{
            id: 1,
            vector: [0.1, 0.2, 0.3],
            attributes: %{"text" => "Sample document", "category" => "doc"}
          }
        ],
        distance_metric: "cosine_distance",
        schema: %{
          "text" => %{"type" => "string", "full_text_search" => true}
        }
      )

      # Upsert with flat attributes (attributes directly in the map)
      Turbopuffer.Vector.write(namespace,
        upsert_rows: [
          %{
            id: 2,
            vector: [0.4, 0.5, 0.6],
            text: "Another document",
            category: "doc"
          }
        ]
      )

      # Delete vectors by ID
      Turbopuffer.Vector.write(namespace,
        deletes: [1, 2, 3]
      )
  """
  @spec write(Namespace.t(), keyword()) ::
          {:ok, Turbopuffer.success_response()} | {:error, term()}
  def write(%Namespace{} = namespace, opts \\ []) do
    path = "/v2/namespaces/#{namespace.name}"

    body =
      opts
      |> Keyword.validate!(@write_options)
      |> Enum.flat_map(&write_field/1)
      |> Map.new()

    Client.post(namespace.client, path, body,
      respond_async: Map.has_key?(body, "copy_from_namespace")
    )
  end

  defp write_field({_key, nil}), do: []
  defp write_field({key, []}) when key in [:upsert_rows, :patch_rows, :deletes], do: []

  defp write_field({key, rows}) when key in [:upsert_rows, :patch_rows],
    do: [{Atom.to_string(key), format_write_vectors(rows)}]

  defp write_field({key, value}), do: [{Atom.to_string(key), value}]

  @doc """
  Queries vectors by similarity.

  ## Options
    * `:vector` - The query vector (required). Pass `{:embed, text}` or `{:embed, text, model}` to have
      turbopuffer embed the text (https://turbopuffer.com/docs/embedding)
    * `:vector_attribute` - The attribute to search (default: "vector"). For native embedding, the
      string attribute that has `embed` in the schema
    * `:top_k` - Number of results to return (default: 10)
    * `:include_attributes` - List of attributes to include in results, `true` or `:all` for all of
      them, or `false` for none (default: true)
    * `:include_vectors` - Whether to include `:vector_attribute` in results, as each result's
      `vector` (default: false). Not allowed with `{:embed, ...}`, whose vector attribute only the
      schema knows: list it in `:include_attributes` instead
    * `:exclude_attributes` - List of attributes to leave out of the results, instead of
      `:include_attributes`
    * `:filters` - A map of attribute values to match, or a turbopuffer filter like
      `["price", "Gte", 10]`
    * `:vector_encoding` - `:float` (the default), or `:base64` to return each vector as
      turbopuffer's base64 string of its little-endian elements, in the attribute's own element type
    * `:consistency` - `:strong` (the default) or `:eventual`

  Unknown options raise `ArgumentError`.

  ## Examples

      # Basic query
      Turbopuffer.Vector.query(namespace,
        vector: [0.1, 0.2, 0.3],
        top_k: 10
      )

      # Query with specific attributes and filters
      Turbopuffer.Vector.query(namespace,
        vector: [0.1, 0.2, 0.3],
        top_k: 5,
        include_attributes: ["text", "category"],
        filters: %{"category" => "doc", "public" => true}
      )

      # Include vectors in results
      Turbopuffer.Vector.query(namespace,
        vector: [0.1, 0.2, 0.3],
        top_k: 10,
        include_vectors: true
      )

      # Search a string attribute that turbopuffer embeds
      Turbopuffer.Vector.query(namespace,
        vector: {:embed, "foxes that jump"},
        vector_attribute: "content"
      )
  """
  @spec query(Namespace.t(), Turbopuffer.vector_query_opts()) ::
          {:ok, Turbopuffer.query_response()} | {:error, term()}
  def query(%Namespace{} = namespace, opts) do
    Keyword.validate!(opts, @query_options)
    vector = Keyword.fetch!(opts, :vector)
    vector_attribute = Keyword.get(opts, :vector_attribute, "vector")

    body =
      %{
        "rank_by" => RankBy.ann(vector_attribute, vector),
        "top_k" => Keyword.get(opts, :top_k, 10)
      }
      |> Map.merge(attributes(opts, vector, vector_attribute))
      |> Query.put_filters(opts[:filters])
      |> put_option("vector_encoding", opts[:vector_encoding], &encoding/1)
      |> Query.put_consistency(opts[:consistency])

    namespace.client
    |> Client.post("/v2/namespaces/#{namespace.name}/query", body)
    |> Query.results(if is_list(vector), do: vector_attribute)
  end

  # turbopuffer's include_attributes: true returns vectors too, so leaving them out takes
  # exclude_attributes, which turbopuffer won't take alongside include_attributes.
  defp attributes(opts, vector, vector_attribute) do
    include = Query.normalize_include_attributes(Keyword.get(opts, :include_attributes, true))
    include_vectors = Keyword.get(opts, :include_vectors, false)
    exclude = Keyword.get(opts, :exclude_attributes)

    if include_vectors and not is_list(vector) do
      raise ArgumentError,
            "include_vectors can't tell which attribute holds the vector for #{inspect(vector)}, " <>
              "so add that attribute to :include_attributes instead"
    end

    if exclude && Keyword.has_key?(opts, :include_attributes) do
      raise ArgumentError,
            "turbopuffer takes :include_attributes or :exclude_attributes, not both"
    end

    case include do
      true when include_vectors and is_list(exclude) ->
        %{"exclude_attributes" => exclude -- [vector_attribute]}

      true when include_vectors ->
        %{"include_attributes" => true}

      # The vector of an embedded query lives in an attribute only the schema names.
      true when is_list(vector) ->
        %{"exclude_attributes" => Enum.uniq([vector_attribute | exclude || []])}

      true when is_list(exclude) ->
        %{"exclude_attributes" => exclude}

      true ->
        %{"include_attributes" => true}

      false when include_vectors ->
        %{"include_attributes" => [vector_attribute]}

      false ->
        %{"include_attributes" => false}

      attributes when include_vectors ->
        %{"include_attributes" => Enum.uniq([vector_attribute | attributes])}

      attributes ->
        %{"include_attributes" => attributes}
    end
  end

  defp put_option(body, _key, nil, _format), do: body
  defp put_option(body, key, value, format), do: Map.put(body, key, format.(value))

  defp encoding(:float), do: "float"
  defp encoding(:base64), do: "base64"

  defp encoding(other) do
    raise ArgumentError, "invalid :vector_encoding #{inspect(other)}, expected :float or :base64"
  end

  # Format vectors for write operations - attributes are flattened
  defp format_write_vectors(vectors) do
    Enum.map(vectors, &format_single_vector/1)
  end

  defp format_single_vector(vector) do
    # Extract id and vector
    id = Map.get(vector, :id) || Map.get(vector, "id")
    vec = Map.get(vector, :vector) || Map.get(vector, "vector")
    attributes = Map.get(vector, :attributes) || Map.get(vector, "attributes")

    base = %{}
    base = if id, do: Map.put(base, "id", id), else: base
    base = if vec, do: Map.put(base, "vector", vec), else: base

    if attributes do
      # If attributes exist as a separate key, merge them
      Map.merge(base, attributes)
    else
      # Otherwise, all other keys are attributes
      vector
      |> Map.drop([:id, "id", :vector, "vector", :attributes, "attributes"])
      |> Map.merge(base)
    end
  end
end
