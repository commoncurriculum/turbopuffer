defmodule Turbopuffer.NamespaceTest do
  use Turbopuffer.IntegrationCase, async: true

  test "list_namespaces pages through the namespaces with a prefix", context do
    %{client: client, prefix: prefix} = context

    for suffix <- ~w(a b c) do
      {:ok, _} = Turbopuffer.write(namespace(context, suffix), upsert_rows: [%{id: 1, n: 1}])
    end

    assert {:ok, %{namespaces: first_page, next_cursor: cursor}} =
             Turbopuffer.list_namespaces(client, prefix: prefix, page_size: 2)

    assert length(first_page) == 2 and is_binary(cursor)

    assert {:ok, %{namespaces: last_page, next_cursor: nil}} =
             Turbopuffer.list_namespaces(client, prefix: prefix, page_size: 2, cursor: cursor)

    assert Enum.sort(Enum.map(first_page ++ last_page, & &1["id"])) ==
             Enum.map(~w(a b c), &"#{prefix}-#{&1}")
  end

  test "delete_namespace deletes a namespace with its documents",
       %{namespace: namespace} = context do
    {:ok, _} = Turbopuffer.write(namespace, upsert_rows: [%{id: 1, n: 1}])

    assert {:ok, %{"status" => "OK"}} = Turbopuffer.delete_namespace(namespace)

    assert {:ok, %{namespaces: [], next_cursor: nil}} =
             Turbopuffer.list_namespaces(context.client, prefix: namespace.name)

    assert {:error, {:http_error, 404, %{"error" => _}}} = Turbopuffer.delete_namespace(namespace)
  end

  test "metadata describes a namespace once it's written to", %{namespace: namespace} do
    assert {:error, {:http_error, 404, _}} = Turbopuffer.metadata(namespace)

    {:ok, _} = Turbopuffer.write(namespace, upsert_rows: [%{id: 1, n: 1}])

    assert {:ok, %{"schema" => %{"n" => %{"type" => "int"}}, "approx_row_count" => rows}} =
             Turbopuffer.metadata(namespace)

    assert is_integer(rows)
  end

  test "update_metadata makes a namespace read_only until it's lifted", %{namespace: namespace} do
    {:ok, _} = Turbopuffer.write(namespace, upsert_rows: [%{id: 1, n: 1}])

    assert {:ok, %{"read_only" => true}} = Turbopuffer.update_metadata(namespace, read_only: true)

    assert {:error, {:http_error, _status, %{"error" => message}}} =
             Turbopuffer.write(namespace, upsert_rows: [%{id: 2, n: 2}])

    assert message =~ "read-only"

    assert {:ok, metadata} = Turbopuffer.update_metadata(namespace, read_only: false)
    refute Map.has_key?(metadata, "read_only")
    assert {:ok, _} = Turbopuffer.write(namespace, upsert_rows: [%{id: 2, n: 2}])
  end

  test "warm_cache hints that queries to a namespace are coming", %{namespace: namespace} do
    assert {:error, {:http_error, 404, _}} = Turbopuffer.warm_cache(namespace)
    {:ok, _} = Turbopuffer.write(namespace, upsert_rows: [%{id: 1, n: 1}])
    assert {:ok, %{}} = Turbopuffer.warm_cache(namespace)
  end

  test "recall measures the vector index over random documents, within filters",
       %{namespace: namespace} do
    {:ok, _} =
      Turbopuffer.write(namespace,
        upsert_rows:
          for(i <- 1..20, do: %{id: i, vector: [i * 1.0, 1.0, 0.5], even: rem(i, 2) == 0}),
        distance_metric: "cosine_distance"
      )

    assert {:ok, %{"avg_recall" => recall, "avg_ann_count" => 5.0, "avg_exhaustive_count" => 5.0}} =
             Turbopuffer.recall(namespace, num: 3, top_k: 5)

    assert recall >= 0 and recall <= 1

    assert {:ok, %{"avg_ann_count" => 3.0, "avg_exhaustive_count" => 3.0}} =
             Turbopuffer.recall(namespace, num: 2, top_k: 3, filters: %{"even" => true})
  end
end
