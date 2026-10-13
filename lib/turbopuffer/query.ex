defmodule Turbopuffer.Query do
  @moduledoc false

  alias Turbopuffer.{Client, Result}

  @spec normalize_include_attributes(term()) :: boolean() | [String.t()]
  def normalize_include_attributes(:all), do: true
  def normalize_include_attributes(value) when is_boolean(value), do: value
  def normalize_include_attributes(value) when is_list(value), do: value

  def normalize_include_attributes(value) do
    raise ArgumentError,
          "invalid value for :include_attributes: #{inspect(value)}. " <>
            "Expected a boolean, :all, or a list of attribute name strings"
  end

  @spec exclusive!(keyword(), atom(), atom()) :: :ok
  def exclusive!(opts, a, b) do
    if opts[a] != nil and opts[b] != nil do
      raise ArgumentError, "turbopuffer takes #{inspect(a)} or #{inspect(b)}, not both"
    end

    :ok
  end

  @spec put(map(), String.t(), term()) :: map()
  def put(body, _key, nil), do: body
  def put(body, key, value), do: Map.put(body, key, value)

  @spec put_limit(map(), keyword()) :: map()
  def put_limit(body, opts) do
    exclusive!(opts, :top_k, :limit)

    case opts[:limit] do
      nil -> Map.put(body, "top_k", Keyword.get(opts, :top_k, 10))
      limit -> Map.put(body, "limit", limit)
    end
  end

  @spec put_attributes(map(), keyword()) :: map()
  def put_attributes(body, opts) do
    exclusive!(opts, :include_attributes, :exclude_attributes)

    case opts[:exclude_attributes] do
      nil ->
        include = Keyword.get(opts, :include_attributes, true)
        Map.put(body, "include_attributes", normalize_include_attributes(include))

      exclude ->
        Map.put(body, "exclude_attributes", exclude)
    end
  end

  @spec put_vector_encoding(map(), :float | :base64 | nil) :: map()
  def put_vector_encoding(body, nil), do: body
  def put_vector_encoding(body, :float), do: Map.put(body, "vector_encoding", "float")
  def put_vector_encoding(body, :base64), do: Map.put(body, "vector_encoding", "base64")

  def put_vector_encoding(_body, other) do
    raise ArgumentError, "invalid :vector_encoding #{inspect(other)}, expected :float or :base64"
  end

  @spec format_filters(Turbopuffer.filters() | list() | nil) :: list() | nil
  def format_filters(nil), do: nil

  def format_filters(filters) when is_map(filters) do
    conditions =
      Enum.map(filters, fn {key, value} ->
        [to_string(key), "Eq", value]
      end)

    case conditions do
      [single] -> single
      multiple -> ["And" | [multiple]]
    end
  end

  def format_filters(filters), do: filters

  @spec put_filters(map(), Turbopuffer.filters() | list() | nil) :: map()
  def put_filters(body, nil), do: body
  def put_filters(body, filters), do: Map.put(body, "filters", format_filters(filters))

  @spec put_consistency(map(), :strong | :eventual | nil) :: map()
  def put_consistency(body, nil), do: body

  def put_consistency(body, level) when level in [:strong, :eventual],
    do: Map.put(body, "consistency", %{"level" => Atom.to_string(level)})

  def put_consistency(_body, level) do
    raise ArgumentError, "invalid :consistency #{inspect(level)}, expected :strong or :eventual"
  end

  @spec results(Client.response(), String.t() | nil) ::
          {:ok, Turbopuffer.query_response()} | {:error, term()}
  def results(response, vector_attribute \\ "vector")

  def results({:ok, %{"rows" => rows}}, vector_attribute) when is_list(rows),
    do: {:ok, Result.from_maps(rows, vector_attribute)}

  def results({:ok, _response}, _vector_attribute), do: {:ok, []}
  def results(error, _vector_attribute), do: error
end
