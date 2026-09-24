defmodule Turbopuffer.Integration.WriteOptionsTest do
  use ExUnit.Case, async: true

  @moduletag :integration

  setup do
    client = Turbopuffer.new(api_key: System.fetch_env!("TURBOPUFFER_API_KEY"))
    name = "turbopuffer-ex-test-" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
    namespace = Turbopuffer.namespace(client, name)
    on_exit(fn -> Turbopuffer.delete_namespace(namespace) end)
    {:ok, namespace: namespace}
  end

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
