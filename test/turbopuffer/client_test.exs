defmodule Turbopuffer.ClientTest do
  use ExUnit.Case, async: true

  describe "new/1" do
    test "defaults to gcp-us-central1" do
      assert Turbopuffer.new(api_key: "key").base_url == "https://gcp-us-central1.turbopuffer.com"
    end

    test "takes any region as a string or an atom" do
      assert Turbopuffer.new(api_key: "key", region: "aws-us-east-1").base_url ==
               "https://aws-us-east-1.turbopuffer.com"

      assert Turbopuffer.new(api_key: "key", region: :aws_ap_southeast_2).base_url ==
               "https://aws-ap-southeast-2.turbopuffer.com"
    end

    test "prefers :base_url over :region" do
      client =
        Turbopuffer.new(api_key: "key", region: "not a region", base_url: "http://localhost:4000")

      assert client.base_url == "http://localhost:4000"
    end

    test "takes the API key from :api_key or TURBOPUFFER_API_KEY, and raises without one" do
      assert Turbopuffer.new(api_key: "key").api_key == "key"

      case System.get_env("TURBOPUFFER_API_KEY") do
        nil -> assert_raise ArgumentError, ~r/API key is required/, fn -> Turbopuffer.new([]) end
        key -> assert Turbopuffer.new([]).api_key == key
      end
    end

    test "rejects malformed regions" do
      assert_raise ArgumentError, ~r/invalid turbopuffer region "us east"/, fn ->
        Turbopuffer.new(api_key: "key", region: "us east")
      end
    end
  end
end
