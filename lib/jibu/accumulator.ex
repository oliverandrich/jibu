defmodule Jibu.Accumulator do
  @moduledoc false

  # Builds the final message from the events of a Messages API stream.
  # Blocks are keyed by their stream index. Tool input JSON collects until its block stops.

  # Delta types that append their text to the block field of the same name.
  @appends %{
    "text_delta" => "text",
    "thinking_delta" => "thinking",
    "signature_delta" => "signature"
  }

  @spec new() :: map()
  def new, do: %{message: %{}, blocks: %{}, json: %{}}

  @spec add(map(), map()) :: map()
  def add(acc, %{"type" => "message_start", "message" => message}) do
    blocks = message |> Map.get("content", []) |> Enum.with_index(&{&2, &1}) |> Map.new()
    %{acc | message: message, blocks: blocks}
  end

  def add(acc, %{"type" => "content_block_start", "index" => index, "content_block" => block}),
    do: put_in(acc.blocks[index], block)

  def add(acc, %{"type" => "content_block_delta", "index" => index, "delta" => delta}) do
    case delta do
      %{"type" => "input_json_delta", "partial_json" => json} ->
        update_in(acc.json, &Map.update(&1, index, [json], fn parts -> [parts, json] end))

      delta ->
        update_block(acc, index, &apply_delta(&1, delta))
    end
  end

  def add(acc, %{"type" => "content_block_stop", "index" => index}) do
    case Map.pop(acc.json, index) do
      {nil, _json} ->
        acc

      {parts, json} ->
        update_block(%{acc | json: json}, index, &put_input(&1, parts))
    end
  end

  def add(acc, %{"type" => "message_delta"} = event) do
    usage = event["usage"] || %{}

    message =
      acc.message
      |> Map.merge(Map.get(event, "delta", %{}))
      |> Map.update("usage", usage, &Map.merge(&1 || %{}, usage))

    %{acc | message: message}
  end

  def add(acc, _event), do: acc

  @spec message(map()) :: map()
  def message(%{message: message, blocks: blocks}) do
    content = blocks |> Enum.sort() |> Enum.map(fn {_index, block} -> block end)
    Map.put(message, "content", content)
  end

  # A block that never started is ignored rather than created from a delta.
  defp update_block(acc, index, fun) do
    case acc.blocks do
      %{^index => block} -> put_in(acc.blocks[index], fun.(block))
      _missing -> acc
    end
  end

  defp apply_delta(block, %{"type" => "citations_delta", "citation" => citation}),
    do: Map.update(block, "citations", [citation], &(&1 ++ [citation]))

  defp apply_delta(block, %{"type" => type} = delta) when is_map_key(@appends, type) do
    key = @appends[type]
    text = Map.get(delta, key, "")
    Map.update(block, key, text, &(&1 <> text))
  end

  defp apply_delta(block, _unknown), do: block

  # Input that does not decode, for example after max_tokens, stays as the raw JSON text.
  defp put_input(block, parts) do
    case IO.iodata_to_binary(parts) do
      "" ->
        block

      json ->
        case JSON.decode(json) do
          {:ok, input} -> Map.put(block, "input", input)
          {:error, _reason} -> Map.put(block, "input", json)
        end
    end
  end
end
