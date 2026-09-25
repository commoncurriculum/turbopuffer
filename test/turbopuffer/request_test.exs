defmodule Turbopuffer.RequestTest do
  use Turbopuffer.IntegrationCase, async: true

  alias Turbopuffer.Client

  test "get, post, and delete send turbopuffer's requests and decode its JSON",
       %{client: client, namespace: namespace} do
    path = "/v2/namespaces/#{namespace.name}"

    assert {:ok, %{"rows_upserted" => 1}} =
             Client.post(client, path, %{"upsert_rows" => [%{"id" => "a", "text" => "héllo ✓"}]})

    assert {:ok, %{"schema" => %{"text" => %{"type" => "string"}}}} =
             Client.get(client, "/v1/namespaces/#{namespace.name}/metadata")

    assert documents(namespace) == %{"a" => %{"text" => "héllo ✓"}}
    assert {:ok, %{"status" => "ok"}} = Client.delete(client, path)
  end

  test "turbopuffer's errors come back with their status and body, without a retry" do
    client = Turbopuffer.new(api_key: "not-a-turbopuffer-key")

    {result, requests} = requests(fn -> Turbopuffer.list_namespaces(client) end)

    assert {:error, {:http_error, 401, %{"error" => _}}} = result
    assert length(requests) == 1
  end

  test "request options go to Finch", %{client: client, prefix: prefix} do
    path = "/v1/namespaces?prefix=#{prefix}"

    assert {:ok, %{}} =
             Client.get(client, path,
               pool_timeout: 5_000,
               receive_timeout: 15_000,
               request_timeout: 15_000
             )

    # Finch returns Mint.TransportError before 0.22 and Finch.TransportError from 0.22 on.
    assert {:error, %{reason: :timeout}} =
             Client.get(%{client | max_retries: 0}, path, receive_timeout: 1)
  end

  test "a connection error is retried :max_retries times" do
    client =
      Turbopuffer.new(
        api_key: "unused",
        base_url: "http://127.0.0.1:1",
        max_retries: 2,
        retry_delay: 1
      )

    {result, requests} = requests(fn -> Turbopuffer.list_namespaces(client) end)

    assert {:error, %{reason: :econnrefused}} = result
    assert length(requests) == 3
  end

  test "respond_async returns the operation's result once turbopuffer finishes it",
       %{client: client, namespace: source} = context do
    {:ok, _} = Turbopuffer.write(source, upsert_rows: [%{id: "a", color: "red"}])
    copy = namespace(context, "copy")

    {result, [request | polls]} =
      requests(fn ->
        Client.post(
          client,
          "/v2/namespaces/#{copy.name}",
          %{"copy_from_namespace" => source.name},
          respond_async: true
        )
      end)

    assert {:ok, %{"status" => "OK"}} = result
    assert {"prefer", "respond-async"} in request.headers
    assert Enum.all?(polls, &(&1.method == "GET"))
    assert documents(copy) == %{"a" => %{"color" => "red"}}

    # The destination has to be empty.
    assert {:error, {:http_error, status, _}} =
             Client.post(
               client,
               "/v2/namespaces/#{copy.name}",
               %{"copy_from_namespace" => source.name},
               respond_async: true
             )

    assert status in [400, 409]
  end
end
