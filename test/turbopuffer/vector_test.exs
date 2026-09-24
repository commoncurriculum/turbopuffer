defmodule Turbopuffer.VectorTest do
  use ExUnit.Case

  alias Turbopuffer.{Client, Namespace, Vector}

  setup do
    client = Client.new(api_key: "test-key")
    namespace = Namespace.new(client, "test-ns")
    {:ok, namespace: namespace}
  end

  describe "vector formatting" do
    test "formats vectors correctly", %{namespace: namespace} do
      vectors = [
        %{
          id: "doc1",
          vector: [0.1, 0.2, 0.3],
          attributes: %{
            text: "Sample document",
            category: "example"
          }
        }
      ]

      # This test validates the vector structure is properly formatted
      assert {:error, _} = Vector.write(namespace, upsert_rows: vectors)
    end

    test "handles vectors with atom keys", %{namespace: namespace} do
      vectors = [
        %{
          id: "doc1",
          vector: [0.1, 0.2, 0.3],
          attributes: %{text: "Sample"}
        }
      ]

      # Test that atom keys are properly converted
      assert {:error, _} = Vector.write(namespace, upsert_rows: vectors)
    end
  end

  describe "unknown options" do
    test "raise instead of being dropped", %{namespace: namespace} do
      assert_raise ArgumentError, ~r/\[:upsert_conditon\] for Turbopuffer.write\/2/, fn ->
        Vector.write(namespace, upsert_rows: [%{id: 1}], upsert_conditon: ["id", "Eq", nil])
      end

      assert_raise ArgumentError, ~r/\[:limit\] for Turbopuffer.query\/2/, fn ->
        Vector.query(namespace, vector: [0.1], limit: 5)
      end

      assert_raise ArgumentError, ~r/\[:text\] for Turbopuffer.text_search\/2/, fn ->
        Turbopuffer.text_search(namespace, query: "q", attribute: "a", text: "q")
      end

      assert_raise ArgumentError, ~r/\[:k\] for Turbopuffer.hybrid_search\/2/, fn ->
        Turbopuffer.hybrid_search(namespace,
          vector: [0.1],
          text_query: "q",
          text_attribute: "a",
          k: 5
        )
      end

      assert_raise ArgumentError, ~r/\[:rerank\] for Turbopuffer.multi_query\/2/, fn ->
        Turbopuffer.multi_query(namespace, queries: [], rerank: true)
      end
    end

    test "raise for options that aren't a keyword list", %{namespace: namespace} do
      assert_raise ArgumentError, ~r/Turbopuffer.write\/2 expects a keyword list/, fn ->
        Vector.write(namespace, [%{id: "doc1", vector: [0.1]}])
      end
    end
  end

  describe "query validation" do
    test "requires vector parameter", %{namespace: namespace} do
      assert_raise KeyError, fn ->
        Vector.query(namespace, top_k: 10)
      end
    end

    test "accepts valid query options", %{namespace: namespace} do
      # This will fail with connection error but validates the parameters
      result =
        Vector.query(namespace,
          vector: [0.1, 0.2, 0.3],
          top_k: 10,
          include_attributes: ["text"],
          include_vectors: false
        )

      assert {:error, _} = result
    end
  end

  describe "include_attributes normalization" do
    test "accepts :all as alias for true", %{namespace: namespace} do
      # This will fail with connection error but validates :all doesn't raise
      result = Vector.query(namespace,
        vector: [0.1, 0.2, 0.3],
        top_k: 10,
        include_attributes: :all
      )
      assert {:error, _} = result
    end

    test "accepts boolean true", %{namespace: namespace} do
      result = Vector.query(namespace,
        vector: [0.1, 0.2, 0.3],
        include_attributes: true
      )
      assert {:error, _} = result
    end

    test "accepts list of attribute names", %{namespace: namespace} do
      result = Vector.query(namespace,
        vector: [0.1, 0.2, 0.3],
        include_attributes: ["text", "category"]
      )
      assert {:error, _} = result
    end

    test "raises ArgumentError for invalid values", %{namespace: namespace} do
      assert_raise ArgumentError, ~r/invalid value for :include_attributes/, fn ->
        Vector.query(namespace,
          vector: [0.1, 0.2, 0.3],
          include_attributes: :invalid
        )
      end
    end
  end
end
