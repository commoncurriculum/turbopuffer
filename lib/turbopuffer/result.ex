defmodule Turbopuffer.Result do
  @moduledoc """
  Represents a single result from a query operation.
  """

  @type t :: %__MODULE__{
          id: String.t() | integer(),
          dist: float() | nil,
          attributes: map() | nil,
          vector: [float()] | String.t() | nil
        }

  defstruct [:id, :dist, :attributes, :vector]

  @doc """
  Converts a raw API response map to a Result struct.

  `vector` is the value of `vector_attribute` (default: "vector"), and `attributes` holds every
  other field but `id` and the score, `$dist`. A `nil` `vector_attribute` leaves every field in
  `attributes`.
  """
  @spec from_map(map(), String.t() | nil) :: t()
  def from_map(map, vector_attribute \\ "vector") when is_map(map) do
    # Extract known fields
    id = Map.get(map, "id")
    dist = Map.get(map, "dist") || Map.get(map, "$dist")
    vector = Map.get(map, vector_attribute)

    # All other fields are attributes
    reserved_keys = ["id", "dist", "$dist", vector_attribute]

    attributes =
      map
      |> Map.drop(reserved_keys)
      |> case do
        attrs when attrs == %{} -> nil
        attrs -> attrs
      end

    %__MODULE__{
      id: id,
      dist: dist,
      attributes: attributes,
      vector: vector
    }
  end

  @doc """
  Converts a list of raw API response maps to Result structs.
  """
  @spec from_maps([map()], String.t() | nil) :: [t()]
  def from_maps(maps, vector_attribute \\ "vector") when is_list(maps) do
    Enum.map(maps, &from_map(&1, vector_attribute))
  end
end
