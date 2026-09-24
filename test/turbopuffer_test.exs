defmodule TurbopufferTest do
  use ExUnit.Case
  doctest Turbopuffer

  defmodule CustomJSON do
    def encode!(term), do: Jason.encode!(term)
    def decode(binary), do: Jason.decode(binary)
  end

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

    test "accepts any region as a string or an atom" do
      assert Turbopuffer.new(api_key: "test-key", region: "aws-us-east-1").base_url ==
               "https://aws-us-east-1.turbopuffer.com"

      assert Turbopuffer.new(api_key: "test-key", region: :aws_ap_southeast_2).base_url ==
               "https://aws-ap-southeast-2.turbopuffer.com"
    end

    test "prefers :base_url over :region" do
      client =
        Turbopuffer.new(
          api_key: "test-key",
          region: "not a region",
          base_url: "http://localhost:4000"
        )

      assert client.base_url == "http://localhost:4000"
    end

    test "rejects malformed regions" do
      assert_raise ArgumentError, ~r/invalid turbopuffer region "us east"/, fn ->
        Turbopuffer.new(api_key: "test-key", region: "us east")
      end
    end

    test "reaches turbopuffer in a region outside GCP" do
      client = Turbopuffer.new(api_key: "not-a-real-key", region: "aws-us-east-1")
      assert {:error, {:http_error, 401, %{"status" => "error"}}} =
               Turbopuffer.list_namespaces(client)
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

  describe "JSON library" do
    test "defaults to Elixir's JSON when it exists, and Jason otherwise" do
      expected = if Code.ensure_loaded?(JSON), do: JSON, else: Jason
      assert Turbopuffer.new(api_key: "test-key").json_library == expected
    end

    test "comes from the :json_library option, then the application setting" do
      Application.put_env(:turbopuffer, :json_library, Jason)
      on_exit(fn -> Application.delete_env(:turbopuffer, :json_library) end)

      assert Turbopuffer.new(api_key: "test-key").json_library == Jason

      assert Turbopuffer.new(api_key: "test-key", json_library: __MODULE__.CustomJSON).json_library ==
               __MODULE__.CustomJSON
    end

    test "raises when the library isn't available" do
      assert_raise ArgumentError, ~r/JSON library NoSuchJSON is not available/, fn ->
        Turbopuffer.new(api_key: "test-key", json_library: NoSuchJSON)
      end
    end

    test "decodes turbopuffer's responses with the configured library" do
      client = Turbopuffer.new(api_key: "not-a-real-key", json_library: Jason)

      assert {:error, {:http_error, 401, %{"status" => "error", "error" => _}}} =
               Turbopuffer.list_namespaces(client)
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
