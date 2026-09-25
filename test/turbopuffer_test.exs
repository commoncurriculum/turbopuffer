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

    test "raises without API key when env var not set" do
      original_env = System.get_env("TURBOPUFFER_API_KEY")
      System.delete_env("TURBOPUFFER_API_KEY")

      assert_raise ArgumentError, fn ->
        Turbopuffer.new([])
      end

      if original_env, do: System.put_env("TURBOPUFFER_API_KEY", original_env)
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
