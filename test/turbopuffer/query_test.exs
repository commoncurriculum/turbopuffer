defmodule Turbopuffer.QueryTest do
  use ExUnit.Case, async: true

  alias Turbopuffer.{Query, Result}

  describe "normalize_include_attributes/1" do
    test "treats :all as true and passes booleans and lists through" do
      assert Query.normalize_include_attributes(:all) == true
      assert Query.normalize_include_attributes(false) == false
      assert Query.normalize_include_attributes(["text"]) == ["text"]
    end

    test "raises for anything else" do
      assert_raise ArgumentError, ~r/invalid value for :include_attributes: :some/, fn ->
        Query.normalize_include_attributes(:some)
      end
    end
  end

  describe "format_filters/1" do
    test "turns a map into equality filters" do
      assert Query.format_filters(%{category: "sports"}) == ["category", "Eq", "sports"]

      assert Query.format_filters(%{"a" => 1, "b" => 2}) ==
               ["And", [["a", "Eq", 1], ["b", "Eq", 2]]]
    end

    test "passes nil and filter lists through" do
      assert Query.format_filters(nil) == nil
      assert Query.format_filters(["price", "Gte", 10]) == ["price", "Gte", 10]
    end
  end

  describe "results/1" do
    test "reads rows from rows, vectors, or data" do
      for key <- ["rows", "vectors", "data"] do
        assert Query.results({:ok, %{key => [%{"id" => 1, "$dist" => 0.5}]}}) ==
                 {:ok, [%Result{id: 1, dist: 0.5}]}
      end
    end

    test "returns no results for other bodies and passes errors through" do
      assert Query.results({:ok, %{}}) == {:ok, []}
      assert Query.results({:error, :timeout}) == {:error, :timeout}
    end
  end
end
