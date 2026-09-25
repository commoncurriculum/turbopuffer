defmodule Turbopuffer.IntegrationCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  using do
    quote do
      @moduletag :integration
    end
  end

  setup do
    client = Turbopuffer.new(api_key: System.fetch_env!("TURBOPUFFER_API_KEY"))
    name = "turbopuffer-ex-test-" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
    namespace = Turbopuffer.namespace(client, name)
    on_exit(fn -> Turbopuffer.delete_namespace(namespace) end)
    {:ok, namespace: namespace}
  end
end
