defmodule Turbopuffer.Options do
  @moduledoc false

  @doc """
  Raises unless `opts` is a keyword list whose keys are all in `allowed`. A misspelled option
  would otherwise be dropped silently, e.g. turning a conditional write into an unconditional one.
  """
  @spec validate!(term(), [atom()], String.t()) :: :ok
  def validate!(opts, allowed, function) do
    unless Keyword.keyword?(opts) do
      raise ArgumentError, "#{function} expects a keyword list of options, got: #{inspect(opts)}"
    end

    case Keyword.keys(opts) -- allowed do
      [] ->
        :ok

      unknown ->
        raise ArgumentError,
              "unknown option(s) #{inspect(Enum.uniq(unknown))} for #{function}. " <>
                "Valid options: #{Enum.map_join(allowed, ", ", &inspect/1)}"
    end
  end
end
