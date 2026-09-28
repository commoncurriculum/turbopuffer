defmodule Turbopuffer.QueryTest do
  use Turbopuffer.IntegrationCase, async: true

  setup %{namespace: namespace} do
    {:ok, _} =
      Turbopuffer.write(namespace,
        upsert_rows: [
          %{id: "near", vector: [1.0, 0.0], color: "red", size: 1},
          %{id: "mid", vector: [0.8, 0.6], color: "red", size: 2},
          %{id: "far", vector: [0.0, 1.0], color: "blue", size: 3}
        ],
        distance_metric: "cosine_distance"
      )

    :ok
  end

  defp query!(namespace, opts) do
    {:ok, results} = Turbopuffer.query(namespace, Keyword.put_new(opts, :vector, [1.0, 0.0]))
    results
  end

  defp ids(results), do: Enum.map(results, & &1.id)

  test "ranks documents by vector distance, closest first, up to top_k", %{namespace: namespace} do
    assert [near, mid] = query!(namespace, top_k: 2)
    assert {near.id, mid.id} == {"near", "mid"}
    assert_in_delta near.dist, 0.0, 1.0e-6
    assert_in_delta mid.dist, 0.2, 1.0e-6
  end

  test "returns every attribute, and the vector only with include_vectors", %{
    namespace: namespace
  } do
    first = fn opts -> namespace |> query!(opts) |> hd() |> Map.take([:attributes, :vector]) end

    assert first.([]) == %{attributes: %{"color" => "red", "size" => 1}, vector: nil}

    assert first.(include_vectors: true) == %{
             attributes: %{"color" => "red", "size" => 1},
             vector: [1.0, 0.0]
           }

    assert first.(include_attributes: :all) == %{
             attributes: %{"color" => "red", "size" => 1},
             vector: nil
           }

    assert first.(include_attributes: ["size"]) == %{attributes: %{"size" => 1}, vector: nil}

    assert first.(include_attributes: ["size"], include_vectors: true) ==
             %{attributes: %{"size" => 1}, vector: [1.0, 0.0]}

    assert first.(include_attributes: false) == %{attributes: nil, vector: nil}

    assert first.(include_attributes: false, include_vectors: true) == %{
             attributes: nil,
             vector: [1.0, 0.0]
           }

    assert first.(exclude_attributes: ["size"]) == %{attributes: %{"color" => "red"}, vector: nil}

    assert first.(exclude_attributes: ["size"], include_vectors: true) ==
             %{attributes: %{"color" => "red"}, vector: [1.0, 0.0]}
  end

  test "filters take a map of values to match, or turbopuffer's own filter", %{
    namespace: namespace
  } do
    assert ids(query!(namespace, filters: %{"color" => "red"})) == ["near", "mid"]
    assert ids(query!(namespace, filters: %{color: "red", size: 2})) == ["mid"]
    assert ids(query!(namespace, filters: ["size", "Gte", 2])) == ["mid", "far"]
  end

  test "vector_encoding: :base64 returns each vector as turbopuffer's base64 of its elements",
       %{namespace: namespace} do
    assert [%{vector: encoded} | _] =
             query!(namespace, include_vectors: true, vector_encoding: :base64)

    assert Base.decode64!(encoded) == <<1.0::float-32-little, 0.0::float-32-little>>

    assert [%{vector: [1.0, +0.0]} | _] =
             query!(namespace, include_vectors: true, vector_encoding: :float)
  end

  test "consistency reads recent writes, whether strong or eventual", %{namespace: namespace} do
    assert ids(query!(namespace, consistency: :strong)) == ["near", "mid", "far"]
    assert ids(query!(namespace, consistency: :eventual)) == ["near", "mid", "far"]
  end

  test "vector_attribute ranks another vector attribute, which include_vectors returns as the vector",
       context do
    namespace = namespace(context, "embedding")

    {:ok, _} =
      Turbopuffer.write(namespace,
        upsert_rows: [
          %{id: "near", embedding: [1.0, 0.0], text: "cat"},
          %{id: "far", embedding: [0.0, 1.0], text: "dog"}
        ],
        distance_metric: "cosine_distance",
        schema: %{"embedding" => %{"type" => "[2]f32", "ann" => true}}
      )

    assert [near, far] =
             query!(namespace,
               vector: [1.0, 0.1],
               vector_attribute: "embedding",
               include_vectors: true
             )

    assert {near.id, near.attributes, near.vector} == {"near", %{"text" => "cat"}, [1.0, 0.0]}
    assert far.id == "far"

    assert [%{attributes: %{"text" => "cat"}, vector: nil} | _] =
             query!(namespace, vector: [1.0, 0.1], vector_attribute: "embedding")
  end

  test "{:embed, text} ranks an attribute turbopuffer embeds, with its own model or a named one",
       context do
    namespace = namespace(context, "embedded")
    model = "openai/text-embedding-3-small"

    {:ok, _} =
      Turbopuffer.write(namespace,
        upsert_rows: [
          %{id: "plants", content: "Plants turn sunlight into sugar through photosynthesis."},
          %{id: "history", content: "The storming of the Bastille began the French Revolution."}
        ],
        distance_metric: "cosine_distance",
        schema: %{
          "content" => %{"type" => "string", "full_text_search" => true, "embed" => model}
        }
      )

    for vector <- [
          {:embed, "how do leaves make food?"},
          {:embed, "how do leaves make food?", model}
        ] do
      assert [%{id: "plants", vector: nil, attributes: %{"content" => "Plants" <> _}} | _] =
               query!(namespace, vector: vector, vector_attribute: "content")

      assert {:ok, [%{id: "plants"} | _]} =
               Turbopuffer.hybrid_search(namespace,
                 vector: vector,
                 vector_attribute: "content",
                 text_query: "sunlight",
                 text_attribute: "content"
               )
    end
  end

  test "a namespace that doesn't exist is a 404", context do
    assert {:error, {:http_error, 404, %{"error" => _}}} =
             Turbopuffer.query(namespace(context, "missing"), vector: [1.0, 0.0])
  end

  describe "aggregate/2" do
    test "counts and sums the documents a filter matches, or all of them", %{namespace: namespace} do
      assert {:ok, aggregations} =
               Turbopuffer.aggregate(namespace,
                 aggregate_by: %{"count" => ["Count"], "total" => ["Sum", "size"]}
               )

      assert aggregations == %{"count" => 3, "total" => 6}

      assert {:ok, aggregations} =
               Turbopuffer.aggregate(namespace,
                 aggregate_by: %{"count" => ["Count"]},
                 filters: %{"color" => "red"},
                 consistency: :eventual
               )

      assert aggregations == %{"count" => 2}
    end

    test "group_by aggregates each group, ordered by the group, up to top_k groups",
         %{namespace: namespace} do
      aggregate_by = %{"count" => ["Count"], "total" => ["Sum", "size"]}

      assert {:ok, groups} =
               Turbopuffer.aggregate(namespace, aggregate_by: aggregate_by, group_by: ["color"])

      assert groups == [
               %{"color" => "blue", "count" => 1, "total" => 3},
               %{"color" => "red", "count" => 2, "total" => 3}
             ]

      assert {:ok, [%{"color" => "blue"}]} =
               Turbopuffer.aggregate(namespace,
                 aggregate_by: aggregate_by,
                 group_by: ["color"],
                 top_k: 1
               )
    end
  end
end
