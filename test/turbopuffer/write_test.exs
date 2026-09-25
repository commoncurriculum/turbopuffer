defmodule Turbopuffer.WriteTest do
  use Turbopuffer.IntegrationCase, async: true

  defp write!(namespace, opts) do
    {:ok, response} = Turbopuffer.write(namespace, opts)
    response
  end

  test "upsert_rows takes each row's attributes flat or under :attributes, with atom or string keys",
       %{namespace: namespace} do
    assert %{"rows_upserted" => 3} =
             write!(namespace,
               upsert_rows: [
                 %{id: "a", vector: [1.0, 0.0], attributes: %{"color" => "red"}},
                 %{"id" => "b", "vector" => [0.0, 1.0], "color" => "blue"},
                 %{id: "c", vector: [0.5, 0.5], color: "green", size: 3}
               ],
               distance_metric: "cosine_distance"
             )

    assert documents(namespace) == %{
             "a" => %{"vector" => [1.0, 0.0], "color" => "red"},
             "b" => %{"vector" => [0.0, 1.0], "color" => "blue"},
             "c" => %{"vector" => [0.5, 0.5], "color" => "green", "size" => 3}
           }
  end

  test "upsert_columns and patch_columns write documents laid out by column",
       %{namespace: namespace} do
    assert %{"rows_upserted" => 2} =
             write!(namespace,
               upsert_columns: %{
                 "id" => ["a", "b"],
                 "vector" => [[1.0, 0.0], [0.0, 1.0]],
                 "color" => ["red", "blue"]
               },
               distance_metric: "cosine_distance"
             )

    assert %{"rows_patched" => 1} =
             write!(namespace, patch_columns: %{"id" => ["b"], "color" => ["green"]})

    assert documents(namespace) == %{
             "a" => %{"vector" => [1.0, 0.0], "color" => "red"},
             "b" => %{"vector" => [0.0, 1.0], "color" => "green"}
           }
  end

  test "patch_rows changes only the attributes given, and deletes removes documents",
       %{namespace: namespace} do
    write!(namespace,
      upsert_rows: [
        %{id: "a", vector: [1.0, 0.0], color: "red", size: 1},
        %{id: "b", vector: [0.0, 1.0], color: "blue", size: 2}
      ],
      distance_metric: "cosine_distance"
    )

    assert %{"rows_patched" => 1, "rows_deleted" => 1} =
             write!(namespace,
               patch_rows: [%{id: "a", color: "pink"}],
               deletes: ["b"],
               disable_backpressure: true
             )

    assert documents(namespace) == %{
             "a" => %{"vector" => [1.0, 0.0], "color" => "pink", "size" => 1}
           }
  end

  test "a write with nothing to write leaves the namespace as it is", %{namespace: namespace} do
    write!(namespace, upsert_rows: [%{id: "a", color: "red"}])

    assert {:ok, _} = Turbopuffer.write(namespace, upsert_rows: [], patch_rows: [], deletes: [])
    assert documents(namespace) == %{"a" => %{"color" => "red"}}
  end

  test "conditions skip the documents whose condition fails", %{namespace: namespace} do
    write!(namespace, upsert_rows: [%{id: "a", version: 1}, %{id: "b", version: 1}])

    assert %{"rows_affected" => 1} =
             write!(namespace,
               upsert_rows: [%{id: "a", version: 2}, %{id: "b", version: 0}],
               upsert_condition: ["version", "Lt", ["$ref_new", "version"]]
             )

    assert %{"rows_affected" => 1} =
             write!(namespace,
               patch_rows: [%{id: "a", color: "red"}, %{id: "b", color: "red"}],
               patch_condition: ["version", "Eq", 2]
             )

    assert %{"rows_affected" => 1} =
             write!(namespace, deletes: ["a", "b"], delete_condition: ["version", "Eq", 1])

    assert documents(namespace) == %{"a" => %{"version" => 2, "color" => "red"}}
  end

  test "patch_by_filter and delete_by_filter write every document a filter matches",
       %{namespace: namespace} do
    write!(namespace,
      upsert_rows: [%{id: "a", color: "red"}, %{id: "b", color: "red"}, %{id: "c", color: "blue"}]
    )

    patched =
      write!(namespace,
        patch_by_filter: %{filters: ["color", "Eq", "red"], patch: %{color: "pink"}},
        patch_by_filter_allow_partial: true
      )

    assert patched["rows_patched"] == 2
    refute patched["rows_remaining"]

    deleted =
      write!(namespace,
        delete_by_filter: ["color", "Eq", "pink"],
        delete_by_filter_allow_partial: true
      )

    assert deleted["rows_deleted"] == 2
    refute deleted["rows_remaining"]

    assert documents(namespace) == %{"c" => %{"color" => "blue"}}
  end

  test "return_affected_ids returns the ids each kind of write changed", %{namespace: namespace} do
    write!(namespace, upsert_rows: [%{id: "a", color: "red"}, %{id: "b", color: "blue"}])

    assert %{"upserted_ids" => ["c"], "patched_ids" => ["a"], "deleted_ids" => ["b"]} =
             write!(namespace,
               upsert_rows: [%{id: "c", color: "green"}],
               patch_rows: [%{id: "a", color: "pink"}],
               deletes: ["b"],
               return_affected_ids: true
             )
  end

  test "schema and distance_metric configure the attributes and the vector index",
       %{namespace: namespace} do
    write!(namespace,
      upsert_rows: [%{id: 1, vector: [0.5, 1.5], text: "Foxes jump", tags: ["a"]}],
      distance_metric: "euclidean_squared",
      schema: %{
        "vector" => %{"type" => "[2]f16", "ann" => true},
        "text" => %{"type" => "string", "full_text_search" => %{"language" => "french"}},
        "tags" => %{"type" => "[]string", "filterable" => false}
      }
    )

    schema = metadata(namespace)["schema"]
    assert schema["vector"]["type"] == "[2]f16"
    assert schema["vector"]["ann"]["distance_metric"] == "euclidean_squared"
    assert schema["text"]["full_text_search"]["language"] == "french"
    assert schema["tags"]["filterable"] == false

    assert documents(namespace) == %{
             1 => %{"vector" => [0.5, 1.5], "text" => "Foxes jump", "tags" => ["a"]}
           }
  end

  test "sharding partitions a new namespace", %{namespace: namespace} do
    write!(namespace, upsert_rows: [%{id: "a", color: "red"}], sharding: %{num_shards: 2})

    assert metadata(namespace)["sharding"] == %{"num_shards" => 2}
    assert documents(namespace) == %{"a" => %{"color" => "red"}}
  end

  test "copy_from_namespace copies every document, from a namespace named alone or with its region and key",
       %{namespace: source} = context do
    write!(source,
      upsert_rows: [%{id: "a", vector: [1.0, 0.0], color: "red"}, %{id: "b", vector: [0.0, 1.0]}],
      distance_metric: "cosine_distance"
    )

    copy = namespace(context, "copy")

    {result, [copy_request | polls]} =
      requests(fn -> Turbopuffer.write(copy, copy_from_namespace: source.name) end)

    assert {:ok, _} = result
    assert {"prefer", "respond-async"} in copy_request.headers
    assert Enum.all?(polls, &(&1.method == "GET"))
    assert documents(copy) == documents(source)

    regional = namespace(context, "regional")

    write!(regional,
      copy_from_namespace: %{
        source_namespace: source.name,
        source_region: "gcp-us-central1",
        source_api_key: System.fetch_env!("TURBOPUFFER_API_KEY")
      }
    )

    assert documents(regional) == documents(source)
  end

  test "branch_from_namespace makes an independent copy-on-write namespace",
       %{namespace: source} = context do
    write!(source, upsert_rows: [%{id: "a", color: "red"}, %{id: "b", color: "blue"}])
    branch = namespace(context, "branch")

    write!(branch, branch_from_namespace: source.name)
    write!(branch, deletes: ["a"])

    assert documents(branch) == %{"b" => %{"color" => "blue"}}
    assert documents(source) == %{"a" => %{"color" => "red"}, "b" => %{"color" => "blue"}}
  end

  test "turbopuffer's rejection comes back as an error with its status and message",
       %{namespace: namespace} do
    write!(namespace,
      upsert_rows: [%{id: "a", count: 1}],
      schema: %{"count" => %{"type" => "int"}}
    )

    assert {:error, {:http_error, status, %{"error" => message}}} =
             Turbopuffer.write(namespace, upsert_rows: [%{id: "b", count: "many"}])

    assert status in [400, 422]
    assert message =~ "count"
  end
end
