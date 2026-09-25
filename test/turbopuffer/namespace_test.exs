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

    assert {:ok, %{"status" => "ok"}} = Turbopuffer.delete_namespace(namespace)

    assert {:ok, %{namespaces: [], next_cursor: nil}} =
             Turbopuffer.list_namespaces(context.client, prefix: namespace.name)

    assert {:error, {:http_error, 404, %{"error" => _}}} = Turbopuffer.delete_namespace(namespace)
  end
end
