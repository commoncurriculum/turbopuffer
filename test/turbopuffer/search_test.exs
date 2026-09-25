defmodule Turbopuffer.SearchTest do
  use ExUnit.Case

  @path "/v2/namespaces/ns/query"
  @queries [
    %{rank_by: ["vector", "ANN", [1.0, 0.0]], top_k: 5},
    %{rank_by: ["text", "BM25", "fox"], top_k: 5}
  ]

  setup do
    bypass = Bypass.open()
    client = Turbopuffer.new(api_key: "test-key", base_url: "http://localhost:#{bypass.port}")
    {:ok, bypass: bypass, namespace: Turbopuffer.namespace(client, "ns")}
  end

  defp expect_query(bypass, response) do
    test_pid = self()

    Bypass.expect_once(bypass, "POST", @path, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:body, JSON.decode!(body)})
      Plug.Conn.resp(conn, 200, JSON.encode!(response))
    end)
  end

  describe "multi_query/2" do
    test "sends each query's own top_k and no top-level limit", %{bypass: bypass, namespace: ns} do
      expect_query(bypass, %{"results" => [%{"rows" => [%{"id" => "a"}]}, %{"rows" => []}]})

      assert {:ok, [%{id: "a"}]} = Turbopuffer.multi_query(ns, queries: @queries, top_k: 3)

      assert_received {:body, body}
      assert Map.keys(body) == ["queries"]
      assert Enum.map(body["queries"], & &1["top_k"]) == [5, 5]
    end

    test "rerank_by sends RRF and limits the fused list with top_k", %{
      bypass: bypass,
      namespace: ns
    } do
      fused = [%{"id" => "b", "$dist" => 0.03}, %{"id" => "a", "$dist" => 0.02}]
      expect_query(bypass, %{"results" => [%{"rows" => fused}]})

      assert {:ok, [%{id: "b"}, %{id: "a"}]} =
               Turbopuffer.multi_query(ns,
                 queries: @queries,
                 top_k: 2,
                 rerank_by: {:rrf, weights: [2, 1], rank_constant: 30}
               )

      assert_received {:body, body}
      assert body["rerank_by"] == ["RRF", %{"weights" => [2, 1], "rank_constant" => 30}]
      assert body["limit"] == 2
    end

    test "rerank_by: :rrf takes turbopuffer's defaults", %{bypass: bypass, namespace: ns} do
      expect_query(bypass, %{"results" => [%{"rows" => []}]})

      assert {:ok, []} = Turbopuffer.multi_query(ns, queries: @queries, rerank_by: :rrf)

      assert_received {:body, %{"rerank_by" => ["RRF"], "limit" => 10}}
    end

    test "rejects unknown RRF options and rerankers before sending anything", %{namespace: ns} do
      assert_raise ArgumentError, ~r/unknown keys \[:k\]/, fn ->
        Turbopuffer.multi_query(ns, queries: @queries, rerank_by: {:rrf, k: 60})
      end

      assert_raise ArgumentError, ~r/invalid :rerank_by :mmr/, fn ->
        Turbopuffer.multi_query(ns, queries: @queries, rerank_by: :mmr)
      end
    end
  end

  describe "hybrid_search/2" do
    @hybrid [vector: [1.0, 0.0], text_query: "fox", text_attribute: "text"]

    test "fuses the two rankings with RRF by default", %{bypass: bypass, namespace: ns} do
      expect_query(bypass, %{"results" => [%{"rows" => [%{"id" => "b"}, %{"id" => "a"}]}]})

      assert {:ok, [%{id: "b"}, %{id: "a"}]} =
               Turbopuffer.hybrid_search(ns, @hybrid ++ [top_k: 5])

      assert_received {:body, body}
      assert body["rerank_by"] == ["RRF"]
      assert body["limit"] == 5

      assert [ann, bm25] = body["queries"]
      assert ann["rank_by"] == ["vector", "ANN", [1.0, 0.0]]
      assert bm25["rank_by"] == ["text", "BM25", "fox"]
    end

    test "passes RRF options through", %{bypass: bypass, namespace: ns} do
      expect_query(bypass, %{"results" => [%{"rows" => []}]})

      assert {:ok, []} =
               Turbopuffer.hybrid_search(ns, @hybrid ++ [rerank_by: {:rrf, weights: [2, 1]}])

      assert_received {:body, %{"rerank_by" => ["RRF", %{"weights" => [2, 1]}]}}
    end

    test "rerank_by: nil returns the rows unfused", %{bypass: bypass, namespace: ns} do
      expect_query(bypass, %{
        "results" => [
          %{"rows" => [%{"id" => "a"}, %{"id" => "b"}]},
          %{"rows" => [%{"id" => "b"}, %{"id" => "c"}]}
        ]
      })

      assert {:ok, [%{id: "a"}, %{id: "b"}, %{id: "c"}]} =
               Turbopuffer.hybrid_search(ns, @hybrid ++ [rerank_by: nil])

      assert_received {:body, body}
      assert Map.keys(body) == ["queries"]
    end
  end
end
