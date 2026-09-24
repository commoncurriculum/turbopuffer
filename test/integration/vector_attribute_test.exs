defmodule Turbopuffer.Integration.VectorAttributeTest do
  use ExUnit.Case, async: true

  @moduletag :integration

  setup do
    client = Turbopuffer.new(api_key: System.fetch_env!("TURBOPUFFER_API_KEY"))
    name = "turbopuffer-ex-test-" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
    namespace = Turbopuffer.namespace(client, name)
    on_exit(fn -> Turbopuffer.delete_namespace(namespace) end)
    {:ok, namespace: namespace}
  end

  test "searches a vector attribute not named vector", %{namespace: namespace} do
    {:ok, _} =
      Turbopuffer.write(namespace,
        upsert_rows: [
          %{id: "near", embedding: [1.0, 0.0], text: "cat"},
          %{id: "far", embedding: [0.0, 1.0], text: "dog"}
        ],
        distance_metric: "cosine_distance",
        schema: %{
          "embedding" => %{"type" => "[2]f32", "ann" => true},
          "text" => %{"type" => "string", "full_text_search" => true}
        }
      )

    assert {:ok, [%{id: "near"}, %{id: "far"}]} =
             Turbopuffer.query(namespace, vector: [1.0, 0.1], vector_attribute: "embedding")

    assert {:ok, [%{id: "near"} | _]} =
             Turbopuffer.hybrid_search(namespace,
               vector: [1.0, 0.1],
               vector_attribute: "embedding",
               text_query: "cat",
               text_attribute: "text"
             )
  end

  test "{:embed, text} searches a natively embedded attribute", %{namespace: namespace} do
    {:ok, _} =
      Turbopuffer.write(namespace,
        upsert_rows: [
          %{id: "plants", content: "Plants turn sunlight into sugar through photosynthesis."},
          %{id: "history", content: "The storming of the Bastille began the French Revolution."}
        ],
        distance_metric: "cosine_distance",
        schema: %{
          "content" => %{
            "type" => "string",
            "full_text_search" => true,
            "embed" => "openai/text-embedding-3-small"
          }
        }
      )

    assert {:ok, [%{id: "plants"} | _]} =
             Turbopuffer.query(namespace,
               vector: {:embed, "how do leaves make food?"},
               vector_attribute: "content"
             )

    assert {:ok, [%{id: "plants"} | _]} =
             Turbopuffer.hybrid_search(namespace,
               vector: {:embed, "how do leaves make food?", "openai/text-embedding-3-small"},
               vector_attribute: "content",
               text_query: "sunlight",
               text_attribute: "content"
             )
  end

  test "rejects a malformed query vector", %{namespace: namespace} do
    assert_raise ArgumentError, ~r/invalid :vector "cat"/, fn ->
      Turbopuffer.query(namespace, vector: "cat")
    end
  end
end
