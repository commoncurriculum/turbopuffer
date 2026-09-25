defmodule Turbopuffer.ClientTest do
  use ExUnit.Case, async: true

  alias Turbopuffer.Client

  setup do
    bypass = Bypass.open()
    client = Client.new(api_key: "test-key", base_url: "http://localhost:#{bypass.port}")
    {:ok, bypass: bypass, client: client}
  end

  describe "request options" do
    test "are the ones Finch takes", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "GET", "/v1/namespaces", fn conn ->
        Plug.Conn.resp(conn, 200, ~s({"namespaces": []}))
      end)

      assert {:ok, %{"namespaces" => []}} =
               Client.get(client, "/v1/namespaces",
                 pool_timeout: 1_000,
                 receive_timeout: 1_000,
                 request_timeout: 1_000
               )
    end

    # Well under Finch's default receive_timeout of 15 seconds.
    @tag timeout: 2_000
    test "receive_timeout gives up on a server that doesn't answer" do
      # Not Bypass: when the client hangs up, Bypass reports its still-running handler as crashed.
      {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false])
      {:ok, port} = :inet.port(socket)

      client =
        Client.new(api_key: "test-key", base_url: "http://localhost:#{port}", max_retries: 0)

      # Finch returns Mint.TransportError before 0.22 and Finch.TransportError from 0.22 on.
      assert {:error, %{reason: :timeout}} =
               Client.get(client, "/v1/namespaces", receive_timeout: 50)
    end
  end
end
