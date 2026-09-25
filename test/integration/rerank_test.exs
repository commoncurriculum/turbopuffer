defmodule Turbopuffer.Integration.RerankTest do
  use Turbopuffer.IntegrationCase, async: true

  setup %{namespace: namespace} do
    {:ok, _} =
      Turbopuffer.write(namespace,
        upsert_rows: [
          %{id: "vector-match", vector: [1.0, 0.0], text: "cat"},
          %{id: "text-match", vector: [0.0, 1.0], text: "fox"}
        ],
        distance_metric: "cosine_distance",
        schema: %{"text" => %{"type" => "string", "full_text_search" => true}}
      )

    queries = [
      %{rank_by: ["vector", "ANN", [1.0, 0.0]], top_k: 1},
      %{rank_by: ["text", "BM25", "fox"], top_k: 1}
    ]

    {:ok, queries: queries}
  end

  test "rerank_by: :rrf fuses the queries into one ranking", context do
    %{namespace: namespace, queries: queries} = context

    assert {:ok, [first, second]} =
             Turbopuffer.multi_query(namespace, queries: queries, rerank_by: :rrf)

    assert Enum.sort([first.id, second.id]) == ["text-match", "vector-match"]
    assert_in_delta first.dist, 1 / 61, 0.0001
  end

  test "RRF weights and top_k shape the fused list", %{namespace: namespace, queries: queries} do
    fused = fn weights ->
      {:ok, results} =
        Turbopuffer.multi_query(namespace,
          queries: queries,
          top_k: 1,
          rerank_by: {:rrf, weights: weights, rank_constant: 60}
        )

      Enum.map(results, & &1.id)
    end

    assert fused.([5, 1]) == ["vector-match"]
    assert fused.([1, 5]) == ["text-match"]
  end

  test "hybrid_search passes rerank_by through", %{namespace: namespace} do
    assert {:ok, [first | _]} =
             Turbopuffer.hybrid_search(namespace,
               vector: [0.0, 1.0],
               text_query: "fox",
               text_attribute: "text",
               rerank_by: :rrf
             )

    assert first.id == "text-match"
  end
end
