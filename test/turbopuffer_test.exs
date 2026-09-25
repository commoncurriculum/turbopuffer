defmodule TurbopufferTest do
  use ExUnit.Case
  doctest Turbopuffer

  describe "client creation" do
    test "creates client with API key" do
      client = Turbopuffer.new(api_key: "test-key")
      assert %Turbopuffer.Client{api_key: "test-key"} = client
    end

    test "uses default region" do
      client = Turbopuffer.new(api_key: "test-key")
      assert client.base_url == "https://gcp-us-central1.turbopuffer.com"
    end

    test "accepts custom region" do
      client = Turbopuffer.new(api_key: "test-key", region: :gcp_europe_west4)
      assert client.base_url == "https://gcp-europe-west4.turbopuffer.com"
    end

    test "raises without API key when env var not set" do
      original_env = System.get_env("TURBOPUFFER_API_KEY")
      System.delete_env("TURBOPUFFER_API_KEY")

      assert_raise ArgumentError, fn ->
        Turbopuffer.new([])
      end

      if original_env, do: System.put_env("TURBOPUFFER_API_KEY", original_env)
    end
  end

  describe "JSON" do
    test "encodes request bodies and decodes responses" do
      bypass = Bypass.open()

      Bypass.expect_once(bypass, "POST", "/v2/namespaces/ns", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert Jason.decode!(body) == %{"deletes" => ["a"]}

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"status": "OK", "rows_deleted": 1}))
      end)

      client = Turbopuffer.new(api_key: "test-key", base_url: "http://localhost:#{bypass.port}")

      assert {:ok, %{"status" => "OK", "rows_deleted" => 1}} =
               Turbopuffer.write(Turbopuffer.namespace(client, "ns"), deletes: ["a"])
    end
  end

  describe "namespace" do
    setup do
      client = Turbopuffer.new(api_key: "test-key")
      {:ok, client: client}
    end

    test "creates namespace reference", %{client: client} do
      namespace = Turbopuffer.namespace(client, "test-ns")
      assert %Turbopuffer.Namespace{name: "test-ns"} = namespace
    end
  end

end
