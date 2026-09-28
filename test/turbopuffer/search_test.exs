defmodule Turbopuffer.SearchTest do
  use Turbopuffer.IntegrationCase, async: true

  setup %{namespace: namespace} do
    {:ok, _} =
      Turbopuffer.write(namespace,
        upsert_rows: [
          %{id: "cat", vector: [1.0, 0.0], text: "the cat sat", kind: "pet"},
          %{id: "fox", vector: [0.0, 1.0], text: "the quick fox", kind: "wild"},
          %{id: "dog", vector: [0.6, 0.8], text: "the dog chased the fox", kind: "pet"}
        ],
        distance_metric: "cosine_distance",
        schema: %{"text" => %{"type" => "string", "full_text_search" => true}}
      )

    :ok
  end

  defp ids(results), do: Enum.map(results, & &1.id)

  describe "text_search/2" do
    test "ranks the documents that match by BM25, best first", %{namespace: namespace} do
      assert {:ok, [fox, dog]} =
               Turbopuffer.text_search(namespace, query: "fox", attribute: "text")

      assert {fox.id, dog.id} == {"fox", "dog"}
      assert fox.dist > dog.dist and dog.dist > 0

      assert {:ok, [%{id: "fox"}]} =
               Turbopuffer.text_search(namespace, query: "fox", attribute: "text", top_k: 1)
    end

    test "takes filters and the attributes to return", %{namespace: namespace} do
      assert {:ok, [dog]} =
               Turbopuffer.text_search(namespace,
                 query: "fox",
                 attribute: "text",
                 filters: %{"kind" => "pet"},
                 include_attributes: ["kind"]
               )

      assert {dog.id, dog.attributes} == {"dog", %{"kind" => "pet"}}
    end

    test "an attribute without full-text search is an error", %{namespace: namespace} do
      assert {:error, {:http_error, status, %{"error" => _}}} =
               Turbopuffer.text_search(namespace, query: "pet", attribute: "kind")

      assert status in [400, 422]
    end
  end

  describe "hybrid_search/2" do
    @hybrid [vector: [0.0, 1.0], text_query: "fox", text_attribute: "text"]

    test "fuses the vector and text rankings with reciprocal rank fusion", %{namespace: namespace} do
      assert {:ok, [fox, dog, cat]} = Turbopuffer.hybrid_search(namespace, @hybrid)
      assert ids([fox, dog, cat]) == ["fox", "dog", "cat"]

      # Each ranking adds 1 / (60 + rank): fox and dog are first and second in both, and cat is
      # third in the vector ranking alone.
      assert_in_delta fox.dist, 2 / 61, 1.0e-6
      assert_in_delta dog.dist, 2 / 62, 1.0e-6
      assert_in_delta cat.dist, 1 / 63, 1.0e-6

      assert {:ok, [%{id: "fox"}]} = Turbopuffer.hybrid_search(namespace, @hybrid ++ [top_k: 1])
    end

    test "filters both rankings", %{namespace: namespace} do
      assert {:ok, [dog, cat]} =
               Turbopuffer.hybrid_search(namespace, @hybrid ++ [filters: %{"kind" => "pet"}])

      assert ids([dog, cat]) == ["dog", "cat"]
      assert_in_delta dog.dist, 2 / 61, 1.0e-6
    end

    test "rerank_by takes RRF's options, or nil for the rankings unfused", %{namespace: namespace} do
      assert {:ok, [fox | _]} =
               Turbopuffer.hybrid_search(
                 namespace,
                 @hybrid ++ [rerank_by: {:rrf, weights: [1, 3]}]
               )

      assert_in_delta fox.dist, 4 / 61, 1.0e-6

      assert {:ok, [fox, dog, cat]} =
               Turbopuffer.hybrid_search(namespace, @hybrid ++ [rerank_by: nil])

      assert ids([fox, dog, cat]) == ["fox", "dog", "cat"]
      # Unfused, the first rows are the vector ranking's, so dist is the cosine distance.
      assert_in_delta fox.dist, 0.0, 1.0e-6
    end
  end

  describe "multi_query/2" do
    @nearest_pet %{rank_by: ["vector", "ANN", [1.0, 0.0]], top_k: 1, filters: %{"kind" => "pet"}}
    @best_fox %{rank_by: ["text", "BM25", "fox"], top_k: 1}

    test "returns each query's rows in turn, without repeating a document", %{
      namespace: namespace
    } do
      assert {:ok, results} =
               Turbopuffer.multi_query(namespace, queries: [@nearest_pet, @best_fox])

      assert ids(results) == ["cat", "fox"]

      queries = [
        %{rank_by: [:vector, :ann, [0.0, 1.0]], top_k: 2, include_attributes: ["kind"]},
        %{rank_by: ["text", "BM25", "fox"], top_k: 2}
      ]

      assert {:ok, [fox, dog]} = Turbopuffer.multi_query(namespace, queries: queries)
      assert {fox.id, fox.attributes, dog.id} == {"fox", %{"kind" => "wild"}, "dog"}
    end

    test "rerank_by fuses the queries, weighted, up to top_k", %{namespace: namespace} do
      fused = fn opts ->
        {:ok, results} =
          Turbopuffer.multi_query(namespace, [queries: [@nearest_pet, @best_fox]] ++ opts)

        results
      end

      assert [first, second] = fused.(rerank_by: :rrf)
      assert Enum.sort(ids([first, second])) == ["cat", "fox"]
      assert_in_delta first.dist, 1 / 61, 1.0e-6

      assert ids(fused.(rerank_by: {:rrf, weights: [5, 1]}, top_k: 1)) == ["cat"]
      assert ids(fused.(rerank_by: {:rrf, weights: [1, 5]}, top_k: 1)) == ["fox"]

      assert [%{dist: dist} | _] = fused.(rerank_by: {:rrf, rank_constant: 10})
      assert_in_delta dist, 1 / 11, 1.0e-6
    end
  end
end
