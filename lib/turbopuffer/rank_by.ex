defmodule Turbopuffer.RankBy do
  @moduledoc false

  @spec ann(String.t(), Turbopuffer.ann_query()) :: list()
  def ann(attribute, {:embed, text}) when is_binary(text), do: [attribute, "ANN", ["Embed", text]]

  def ann(attribute, {:embed, text, model}) when is_binary(text) and is_binary(model) do
    [attribute, "ANN", ["Embed", text, %{"model" => model}]]
  end

  def ann(attribute, vector) when is_list(vector), do: [attribute, "ANN", vector]

  def ann(_attribute, other) do
    raise ArgumentError,
          "invalid :vector #{inspect(other)}, expected a list of numbers, {:embed, text}, " <>
            "or {:embed, text, model}"
  end
end
