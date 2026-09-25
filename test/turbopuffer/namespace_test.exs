defmodule Turbopuffer.NamespaceTest do
  use ExUnit.Case

  alias Turbopuffer.{Client, Namespace}

  setup do
    bypass = Bypass.open()
    client = Client.new(api_key: "test-key", base_url: "http://localhost:#{bypass.port}")
    {:ok, client: client, bypass: bypass}
  end

  describe "list/2" do
    test "sends GET to /v1/namespaces with no query params", %{client: client, bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/v1/namespaces", fn conn ->
        assert conn.query_string == ""
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{"namespaces" => ["ns-a", "ns-b"]}))
      end)

      assert {:ok, %{namespaces: ["ns-a", "ns-b"], next_cursor: nil}} = Namespace.list(client)
    end

    test "sends prefix as query param", %{client: client, bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/v1/namespaces", fn conn ->
        params = URI.decode_query(conn.query_string)
        assert params["prefix"] == "prod-"
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{"namespaces" => ["prod-a"]}))
      end)

      assert {:ok, %{namespaces: ["prod-a"], next_cursor: nil}} =
               Namespace.list(client, prefix: "prod-")
    end

    test "sends page_size and cursor as query params", %{client: client, bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/v1/namespaces", fn conn ->
        params = URI.decode_query(conn.query_string)
        assert params["page_size"] == "25"
        assert params["cursor"] == "abc123"
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{
          "namespaces" => ["ns-1", "ns-2"],
          "next_cursor" => "def456"
        }))
      end)

      assert {:ok, %{namespaces: ["ns-1", "ns-2"], next_cursor: "def456"}} =
               Namespace.list(client, page_size: 25, cursor: "abc123")
    end

    test "returns next_cursor when present in response", %{client: client, bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/v1/namespaces", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{
          "namespaces" => ["ns-1"],
          "next_cursor" => "cursor-xyz"
        }))
      end)

      assert {:ok, %{namespaces: ["ns-1"], next_cursor: "cursor-xyz"}} = Namespace.list(client)
    end

    test "returns empty list when no namespaces key in response", %{client: client, bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/v1/namespaces", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{}))
      end)

      assert {:ok, %{namespaces: [], next_cursor: nil}} = Namespace.list(client)
    end

    test "returns error on HTTP error", %{client: client, bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/v1/namespaces", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(401, Jason.encode!(%{"error" => "unauthorized"}))
      end)

      assert {:error, {:http_error, 401, _}} = Namespace.list(client)
    end

    test "ignores unknown options", %{client: client, bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/v1/namespaces", fn conn ->
        assert conn.query_string == ""
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{"namespaces" => []}))
      end)

      assert {:ok, %{namespaces: [], next_cursor: nil}} =
               Namespace.list(client, bogus: "ignored")
    end
  end
end
