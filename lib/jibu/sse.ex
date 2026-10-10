defmodule Jibu.SSE do
  @moduledoc false

  # Parses a Server-Sent Events stream chunk by chunk.
  # The state holds the unparsed rest with normalized line endings.
  # It also records a trailing CR, whose LF may arrive with the next chunk.

  @type event :: %{event: String.t(), data: String.t()}
  @opaque state :: {String.t(), boolean()}

  @spec new() :: state()
  def new, do: {"", false}

  @spec parse(state(), String.t()) :: {[event()], state()}
  def parse(state, ""), do: {[], state}

  def parse({rest, after_cr}, chunk) do
    chunk = if after_cr, do: String.replace_prefix(chunk, "\n", ""), else: chunk
    data = rest <> normalize(chunk)

    # `rest` holds no blank line, so the search starts at its last byte.
    from = max(byte_size(rest) - 1, 0)
    blocks = :binary.split(data, "\n\n", [:global, scope: {from, byte_size(data) - from}])
    {complete, [rest]} = Enum.split(blocks, -1)

    {Enum.flat_map(complete, &event/1), {rest, String.ends_with?(chunk, "\r")}}
  end

  defp normalize(chunk) do
    if String.contains?(chunk, "\r"),
      do: chunk |> String.replace("\r\n", "\n") |> String.replace("\r", "\n"),
      else: chunk
  end

  defp event(block) do
    {name, data} = block |> String.split("\n") |> Enum.reduce({"message", []}, &field/2)
    if data == [], do: [], else: [%{event: name, data: data |> Enum.reverse() |> Enum.join("\n")}]
  end

  defp field(":" <> _comment, acc), do: acc

  defp field(line, {name, data} = acc) do
    case String.split(line, ":", parts: 2) do
      ["event", value] -> {value(value), data}
      ["data", value] -> {name, [value(value) | data]}
      ["data"] -> {name, ["" | data]}
      _other -> acc
    end
  end

  defp value(" " <> value), do: value
  defp value(value), do: value
end
