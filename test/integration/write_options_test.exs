defmodule Turbopuffer.Integration.WriteOptionsTest do
  use Turbopuffer.IntegrationCase, async: true

  test "sends the write options the API documents", %{namespace: namespace} do
    rows = [%{id: "a", color: "red"}, %{id: "b", color: "blue"}]

    assert {:ok, %{"upserted_ids" => ["a", "b"]}} =
             Turbopuffer.write(namespace, upsert_rows: rows, return_affected_ids: true)

    assert {:ok, %{"rows_patched" => 1, "patched_ids" => ["b"]}} =
             Turbopuffer.write(namespace,
               patch_by_filter: %{filters: ["color", "Eq", "blue"], patch: %{color: "green"}},
               return_affected_ids: true
             )
  end
end
