defmodule Turbopuffer.VectorAttributeTest do
  use ExUnit.Case

  setup do
    bypass = Bypass.open()
    client = Turbopuffer.new(api_key: "test-key", base_url: "http://localhost:#{bypass.port}")
    {:ok, bypass: bypass, namespace: Turbopuffer.namespace(client, "ns")}
  end

  defp expect_query(bypass, path, response) do
    test_pid = self()

    Bypass.expect_once(bypass, "POST", path, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:body, Jason.decode!(body)})
      Plug.Conn.resp(conn, 200, Jason.encode!(response))
    end)
  end

  describe "query/2" do
    test "ranks the named vector attribute", %{bypass: bypass, namespace: ns} do
      expect_query(bypass, "/v2/namespaces/ns/query", %{"rows" => [%{"id" => "a"}]})

      assert {:ok, [%{id: "a"}]} =
               Turbopuffer.query(ns,
                 vector: [1.0, 0.0],
                 vector_attribute: "title_vector",
                 include_attributes: ["title"],
                 include_vectors: true
               )

      assert_received {:body, body}
      assert body["rank_by"] == ["title_vector", "ANN", [1.0, 0.0]]
      assert body["include_attributes"] == ["title_vector", "title"]
    end

    test "has turbopuffer embed text, optionally with a model", %{bypass: bypass, namespace: ns} do
      expect_query(bypass, "/v2/namespaces/ns/query", %{"rows" => []})
      assert {:ok, []} = Turbopuffer.query(ns, vector: {:embed, "fox"}, vector_attribute: "text")
      assert_received {:body, %{"rank_by" => ["text", "ANN", ["Embed", "fox"]]}}

      expect_query(bypass, "/v2/namespaces/ns/query", %{"rows" => []})
      assert {:ok, []} = Turbopuffer.query(ns, vector: {:embed, "fox", "some/model"})

      assert_received {:body,
                       %{
                         "rank_by" => [
                           "vector",
                           "ANN",
                           ["Embed", "fox", %{"model" => "some/model"}]
                         ]
                       }}
    end

    test "won't guess the vector attribute of an embedded query", %{namespace: ns} do
      assert_raise ArgumentError, ~r/add that attribute to :include_attributes/, fn ->
        Turbopuffer.query(ns,
          vector: {:embed, "fox"},
          vector_attribute: "text",
          include_vectors: true
        )
      end
    end

    test "rejects a :vector that is neither a list nor an embed", %{namespace: ns} do
      assert_raise ArgumentError, ~r/invalid :vector "fox"/, fn ->
        Turbopuffer.query(ns, vector: "fox")
      end
    end
  end

  describe "hybrid_search/2" do
    test "ranks the named vector attribute next to BM25", %{bypass: bypass, namespace: ns} do
      expect_query(bypass, "/v2/namespaces/ns/query", %{"results" => [%{"rows" => []}]})

      assert {:ok, []} =
               Turbopuffer.hybrid_search(ns,
                 vector: {:embed, "fox"},
                 vector_attribute: "text",
                 text_query: "fox",
                 text_attribute: "text"
               )

      assert_received {:body, %{"queries" => [ann, bm25]}}
      assert ann["rank_by"] == ["text", "ANN", ["Embed", "fox"]]
      assert bm25["rank_by"] == ["text", "BM25", "fox"]
    end
  end
end
