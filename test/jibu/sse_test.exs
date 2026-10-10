defmodule Jibu.SSETest do
  use ExUnit.Case, async: true

  alias Jibu.SSE

  @stream """
  event: message_start
  data: {"type":"message_start"}

  : a comment
  event: ping
  data: {"type": "ping"}

  data: first
  data: second

  """

  @events [
    %{event: "message_start", data: ~s({"type":"message_start"})},
    %{event: "ping", data: ~s({"type": "ping"})},
    %{event: "message", data: "first\nsecond"}
  ]

  defp parse_chunks(chunks) do
    {events, _state} =
      Enum.flat_map_reduce(chunks, SSE.new(), fn chunk, state -> SSE.parse(state, chunk) end)

    events
  end

  test "parses events, joins data lines and skips comments" do
    assert parse_chunks([@stream]) == @events
  end

  test "returns the same events for every split of the stream" do
    for at <- 0..byte_size(@stream) do
      <<head::binary-size(^at), tail::binary>> = @stream
      assert parse_chunks([head, tail]) == @events, "split at byte #{at}"
    end
  end

  test "accepts CRLF and CR line endings, also split between CR and LF" do
    crlf = String.replace(@stream, "\n", "\r\n")
    cr = String.replace(@stream, "\n", "\r")

    assert parse_chunks([crlf]) == @events
    assert parse_chunks([cr]) == @events

    for at <- 0..byte_size(crlf) do
      <<head::binary-size(^at), tail::binary>> = crlf
      assert parse_chunks([head, "", tail]) == @events, "CRLF split at byte #{at}"
    end
  end

  test "keeps an incomplete event until its blank line arrives" do
    {events, state} = SSE.parse(SSE.new(), "event: ping\ndata: {}\n")
    assert events == []
    assert {[%{event: "ping", data: "{}"}], _state} = SSE.parse(state, "\n")
  end
end
