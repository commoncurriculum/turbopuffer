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

  @spec results(Client.response()) :: {:ok, Turbopuffer.query_response()} | {:error, term()}
  def results({:ok, %{"rows" => rows}}) when is_list(rows), do: {:ok, Result.from_maps(rows)}

  def results({:ok, %{"vectors" => vectors}}) when is_list(vectors) do
    {:ok, Result.from_maps(vectors)}
  end

  def results({:ok, %{"data" => data}}) when is_list(data), do: {:ok, Result.from_maps(data)}
  def results({:ok, _response}), do: {:ok, []}
  def results(error), do: error
end
