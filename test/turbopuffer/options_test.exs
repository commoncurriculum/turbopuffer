defmodule Turbopuffer.OptionsTest do
  use ExUnit.Case, async: true

  # Every check here happens before a request is sent, so the client has nowhere to send one.
  setup do
    client = Turbopuffer.new(api_key: "unused", base_url: "http://127.0.0.1:1", max_retries: 0)
    {:ok, client: client, namespace: Turbopuffer.namespace(client, "ns")}
  end

  test "unknown options raise instead of being dropped", %{client: client, namespace: namespace} do
    assert_raise ArgumentError, ~r/unknown keys \[:upsert_conditon\]/, fn ->
      Turbopuffer.write(namespace, upsert_rows: [%{id: 1}], upsert_conditon: ["id", "Eq", nil])
    end

    assert_raise ArgumentError, ~r/unknown keys \[:limit\]/, fn ->
      Turbopuffer.query(namespace, vector: [0.1], limit: 5)
    end

    assert_raise ArgumentError, ~r/unknown keys \[:aggregate_by\]/, fn ->
      Turbopuffer.query(namespace, vector: [0.1], aggregate_by: %{"count" => ["Count"]})
    end

    assert_raise ArgumentError, ~r/unknown keys \[:limit\]/, fn ->
      Turbopuffer.aggregate(namespace, aggregate_by: %{"count" => ["Count"]}, limit: 5)
    end

    assert_raise ArgumentError, ~r/unknown keys \[:text\]/, fn ->
      Turbopuffer.text_search(namespace, query: "q", attribute: "a", text: "q")
    end

    assert_raise ArgumentError, ~r/unknown keys \[:k\]/, fn ->
      Turbopuffer.hybrid_search(namespace,
        vector: [0.1],
        text_query: "q",
        text_attribute: "a",
        k: 5
      )
    end

    assert_raise ArgumentError, ~r/unknown keys \[:rerank\]/, fn ->
      Turbopuffer.multi_query(namespace, queries: [], rerank: true)
    end

    assert_raise ArgumentError, ~r/unknown keys \[:k\]/, fn ->
      Turbopuffer.multi_query(namespace, queries: [], rerank_by: {:rrf, k: 60})
    end

    assert_raise ArgumentError, ~r/unknown keys \[:limit\] in query/, fn ->
      Turbopuffer.multi_query(namespace, queries: [%{rank_by: ["text", "BM25", "q"], limit: 5}])
    end

    assert_raise ArgumentError, ~r/unknown keys \[:size\]/, fn ->
      Turbopuffer.list_namespaces(client, size: 5)
    end
  end

  test "options that aren't a keyword list raise", %{namespace: namespace} do
    assert_raise ArgumentError, ~r/expected a keyword list/, fn ->
      Turbopuffer.write(namespace, [%{id: "doc1", vector: [0.1]}])
    end
  end

  test "values turbopuffer doesn't take raise", %{namespace: namespace} do
    assert_raise ArgumentError, ~r/invalid :vector "fox"/, fn ->
      Turbopuffer.query(namespace, vector: "fox")
    end

    assert_raise ArgumentError, ~r/invalid value for :include_attributes: :some/, fn ->
      Turbopuffer.query(namespace, vector: [0.1], include_attributes: :some)
    end

    assert_raise ArgumentError, ~r/invalid :vector_encoding :hex/, fn ->
      Turbopuffer.query(namespace, vector: [0.1], vector_encoding: :hex)
    end

    assert_raise ArgumentError, ~r/invalid :consistency :weak/, fn ->
      Turbopuffer.aggregate(namespace, aggregate_by: %{"count" => ["Count"]}, consistency: :weak)
    end

    assert_raise ArgumentError, ~r/invalid :rerank_by :mmr/, fn ->
      Turbopuffer.multi_query(namespace, queries: [], rerank_by: :mmr)
    end
  end

  test "attribute options turbopuffer can't combine raise", %{namespace: namespace} do
    assert_raise ArgumentError, ~r/not both/, fn ->
      Turbopuffer.query(namespace,
        vector: [0.1],
        include_attributes: ["a"],
        exclude_attributes: ["b"]
      )
    end

    assert_raise ArgumentError, ~r/add that attribute to :include_attributes/, fn ->
      Turbopuffer.query(namespace,
        vector: {:embed, "fox"},
        vector_attribute: "text",
        include_vectors: true
      )
    end
  end

  test "required options raise when they're missing", %{namespace: namespace} do
    assert_raise KeyError, ~r/:vector/, fn -> Turbopuffer.query(namespace, top_k: 10) end
    assert_raise KeyError, ~r/:aggregate_by/, fn -> Turbopuffer.aggregate(namespace, []) end
  end
end
