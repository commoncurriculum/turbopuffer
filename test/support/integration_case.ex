defmodule Turbopuffer.IntegrationCase do
  @moduledoc """
  Gives each test its own namespaces, named with a random prefix, and deletes them when the test
  finishes, as turbopuffer's testing guide recommends (https://turbopuffer.com/docs/testing).
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      @moduletag :integration
      import Turbopuffer.IntegrationCase
    end
  end

  setup do
    client = Turbopuffer.new(api_key: System.fetch_env!("TURBOPUFFER_API_KEY"))
    prefix = "turbopuffer-ex-test-" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)

    on_exit(fn ->
      {:ok, %{namespaces: namespaces}} = Turbopuffer.list_namespaces(client, prefix: prefix)

      for %{"id" => name} <- namespaces do
        {:ok, _} = Turbopuffer.delete_namespace(Turbopuffer.namespace(client, name))
      end
    end)

    {:ok,
     client: client, prefix: prefix, namespace: Turbopuffer.namespace(client, prefix <> "-main")}
  end

  @doc "Another namespace of the test's, deleted with the rest."
  def namespace(%{client: client, prefix: prefix}, suffix),
    do: Turbopuffer.namespace(client, "#{prefix}-#{suffix}")

  @doc """
  Every document in `namespace` with the attributes it has, by id, read with turbopuffer's API
  rather than the functions under test.
  """
  def documents(namespace) do
    {:ok, %{"rows" => rows}} =
      Turbopuffer.Client.post(namespace.client, "/v2/namespaces/#{namespace.name}/query", %{
        "rank_by" => ["id", "asc"],
        "top_k" => 1_000,
        "include_attributes" => true
      })

    Map.new(rows, fn row ->
      {id, attributes} = Map.pop!(row, "id")
      {id, Map.reject(attributes, fn {_name, value} -> is_nil(value) end)}
    end)
  end

  @doc "The namespace's metadata, read with turbopuffer's API."
  def metadata(namespace) do
    {:ok, metadata} =
      Turbopuffer.Client.get(namespace.client, "/v1/namespaces/#{namespace.name}/metadata")

    metadata
  end

  @doc "Runs `fun`, returning its result and the HTTP requests it sent, as `Finch.Request`s."
  def requests(fun) do
    handler = {__MODULE__, make_ref()}

    :telemetry.attach(
      handler,
      [:finch, :request, :start],
      &__MODULE__.forward/4,
      {self(), handler}
    )

    try do
      result = fun.()
      {result, collect(handler, [])}
    after
      :telemetry.detach(handler)
    end
  end

  @doc false
  def forward(_event, _measurements, %{request: request}, {test, handler}) do
    if self() == test, do: send(test, {handler, request})
  end

  defp collect(handler, requests) do
    receive do
      {^handler, request} -> collect(handler, [request | requests])
    after
      0 -> Enum.reverse(requests)
    end
  end
end
