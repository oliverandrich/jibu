defmodule Jibu.AccumulatorTest do
  use ExUnit.Case, async: true

  alias Jibu.Accumulator

  defp assemble(events),
    do:
      events |> Enum.reduce(Accumulator.new(), &Accumulator.add(&2, &1)) |> Accumulator.message()

  defp start(index, block),
    do: %{"type" => "content_block_start", "index" => index, "content_block" => block}

  defp delta(index, delta),
    do: %{"type" => "content_block_delta", "index" => index, "delta" => delta}

  defp stop(index), do: %{"type" => "content_block_stop", "index" => index}

  @message_start %{
    "type" => "message_start",
    "message" => %{
      "id" => "msg_1",
      "type" => "message",
      "role" => "assistant",
      "model" => "m",
      "content" => [],
      "stop_reason" => nil,
      "usage" => %{"input_tokens" => 10, "output_tokens" => 1}
    }
  }

  test "assembles text blocks, the stop reason and the usage" do
    message =
      assemble([
        @message_start,
        start(0, %{"type" => "text", "text" => ""}),
        %{"type" => "ping"},
        delta(0, %{"type" => "text_delta", "text" => "Hel"}),
        delta(0, %{"type" => "text_delta", "text" => "lo"}),
        stop(0),
        %{
          "type" => "message_delta",
          "delta" => %{"stop_reason" => "end_turn", "stop_sequence" => nil},
          "usage" => %{"output_tokens" => 12}
        },
        %{"type" => "message_stop"}
      ])

    assert message == %{
             "id" => "msg_1",
             "type" => "message",
             "role" => "assistant",
             "model" => "m",
             "content" => [%{"type" => "text", "text" => "Hello"}],
             "stop_reason" => "end_turn",
             "stop_sequence" => nil,
             "usage" => %{"input_tokens" => 10, "output_tokens" => 12}
           }
  end

  test "decodes the input of tool use blocks from partial JSON" do
    message =
      assemble([
        @message_start,
        start(0, %{"type" => "tool_use", "id" => "t1", "name" => "weather", "input" => %{}}),
        delta(0, %{"type" => "input_json_delta", "partial_json" => ""}),
        delta(0, %{"type" => "input_json_delta", "partial_json" => ~s({"city": "Ber)}),
        delta(0, %{"type" => "input_json_delta", "partial_json" => ~s(lin"})}),
        stop(0),
        start(1, %{
          "type" => "server_tool_use",
          "id" => "s1",
          "name" => "web_search",
          "input" => %{}
        }),
        stop(1)
      ])

    assert [
             %{"type" => "tool_use", "input" => %{"city" => "Berlin"}},
             %{"type" => "server_tool_use", "input" => %{}}
           ] = message["content"]
  end

  test "keeps partial JSON that does not decode as the raw input" do
    message =
      assemble([
        @message_start,
        start(0, %{"type" => "tool_use", "id" => "t1", "name" => "weather", "input" => %{}}),
        delta(0, %{"type" => "input_json_delta", "partial_json" => ~s({"city": "Ber)}),
        stop(0)
      ])

    assert [%{"input" => ~s({"city": "Ber)}] = message["content"]
  end

  test "assembles thinking with its signature and text with citations" do
    citation = %{"type" => "char_location", "cited_text" => "x"}

    message =
      assemble([
        @message_start,
        start(0, %{"type" => "thinking", "thinking" => "", "signature" => ""}),
        delta(0, %{"type" => "thinking_delta", "thinking" => "Let me "}),
        delta(0, %{"type" => "thinking_delta", "thinking" => "think"}),
        delta(0, %{"type" => "signature_delta", "signature" => "sig"}),
        stop(0),
        start(1, %{"type" => "text", "text" => ""}),
        delta(1, %{"type" => "citations_delta", "citation" => citation}),
        delta(1, %{"type" => "text_delta", "text" => "cited"}),
        stop(1)
      ])

    assert message["content"] == [
             %{"type" => "thinking", "thinking" => "Let me think", "signature" => "sig"},
             %{"type" => "text", "text" => "cited", "citations" => [citation]}
           ]
  end

  test "ignores unknown events and delta types" do
    message =
      assemble([
        @message_start,
        start(0, %{"type" => "text", "text" => "a"}),
        delta(0, %{"type" => "future_delta", "value" => 1}),
        %{"type" => "future_event"},
        stop(0)
      ])

    assert message["content"] == [%{"type" => "text", "text" => "a"}]
  end

  test "ignores deltas and stops for a block that never started" do
    message =
      assemble([
        @message_start,
        delta(3, %{"type" => "text_delta", "text" => "x"}),
        delta(4, %{"type" => "input_json_delta", "partial_json" => "{}"}),
        stop(4)
      ])

    assert message["content"] == []
  end
end
