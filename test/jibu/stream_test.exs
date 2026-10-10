defmodule Jibu.StreamTest do
  use ExUnit.Case, async: true

  import Jibu.TestHelpers

  alias Jibu.Error
  alias Jibu.Response

  @events [
    %{
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
    },
    %{
      "type" => "content_block_start",
      "index" => 0,
      "content_block" => %{"type" => "text", "text" => ""}
    },
    %{"type" => "ping"},
    %{
      "type" => "content_block_delta",
      "index" => 0,
      "delta" => %{"type" => "text_delta", "text" => "Hel"}
    },
    %{
      "type" => "content_block_delta",
      "index" => 0,
      "delta" => %{"type" => "text_delta", "text" => "lo"}
    },
    %{"type" => "content_block_stop", "index" => 0},
    %{
      "type" => "message_delta",
      "delta" => %{"stop_reason" => "end_turn"},
      "usage" => %{"output_tokens" => 5}
    },
    %{"type" => "message_stop"}
  ]

  # Answers with `sse` in chunks of `size` bytes and reports the decoded request body.
  defp stream_stub(sse, size \\ 7) do
    test_pid = self()

    Req.Test.expect(__MODULE__, fn conn ->
      send(test_pid, {:body, JSON.decode!(Req.Test.raw_body(conn))})

      conn =
        conn
        |> Plug.Conn.put_resp_content_type("text/event-stream")
        |> Plug.Conn.put_resp_header("request-id", "req_1")
        |> Plug.Conn.send_chunked(200)

      sse |> split(size) |> Enum.reduce(conn, &chunk(&2, &1))
    end)
  end

  defp split(data, size) when byte_size(data) <= size, do: [data]

  defp split(data, size) do
    <<head::binary-size(^size), rest::binary>> = data
    [head | split(rest, size)]
  end

  defp chunk(conn, data) do
    {:ok, conn} = Plug.Conn.chunk(conn, data)
    conn
  end

  defp forward do
    test_pid = self()
    fn event -> send(test_pid, {:event, event}) end
  end

  defp received_events(acc \\ []) do
    receive do
      {:event, event} -> received_events([event | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  test "sends stream: true, passes every event to the function and returns the message" do
    stream_stub(sse(@events))
    body = %{model: "m", max_tokens: 10, messages: [%{role: "user", content: "Hi"}]}

    assert {:ok, %Response{} = response} = Jibu.stream(client(__MODULE__), body, forward())

    assert_received {:body, sent}

    assert sent == %{
             "model" => "m",
             "max_tokens" => 10,
             "stream" => true,
             "messages" => [%{"role" => "user", "content" => "Hi"}]
           }

    assert received_events() == @events
    assert Response.text(response) == "Hello"
    assert response.stop_reason == "end_turn"
    assert response.usage == %{"input_tokens" => 10, "output_tokens" => 5}
    assert response.body["id"] == "msg_1"
  end

  test "replaces a stream field under either key with stream: true" do
    stream_stub(sse(@events))

    assert {:ok, _response} =
             Jibu.stream(
               client(__MODULE__),
               %{:stream => false, "model" => "m", "stream" => false},
               fn _event -> :ok end
             )

    assert_received {:body, %{"model" => "m", "stream" => true} = sent}
    assert map_size(sent) == 2
  end

  test "returns an API error before the stream without calling the function" do
    Req.Test.expect(__MODULE__, &api_error(&1, 529, "overloaded_error"))

    assert {:error, %Error{type: "overloaded_error", status: 529, request_id: "req_123"}} =
             Jibu.stream(client(__MODULE__), %{model: "m"}, forward())

    assert received_events() == []
  end

  test "retries an API error before the stream and passes each event once" do
    Req.Test.expect(__MODULE__, &api_error(&1, 529, "overloaded_error"))
    stream_stub(sse(@events))

    client =
      client(__MODULE__, retry: &Jibu.Retry.retry/2, retry_delay: 0, retry_log_level: false)

    assert {:ok, response} = Jibu.stream(client, %{model: "m"}, forward())
    assert Response.text(response) == "Hello"
    assert received_events() == @events
  end

  test "returns an error event as an error with the partial message" do
    error = %{
      "type" => "error",
      "error" => %{"type" => "overloaded_error", "message" => "Overloaded"}
    }

    stream_stub(sse(Enum.take(@events, 4) ++ [error]))

    assert {:error,
            %Error{type: "overloaded_error", message: "Overloaded", request_id: "req_1"} = e} =
             Jibu.stream(client(__MODULE__), %{model: "m"}, forward())

    assert [%{"type" => "text", "text" => "Hel"}] = e.body["content"]
    assert List.last(received_events()) == error
  end

  test "reports the usage of the assembled message in the telemetry span" do
    ref = attach_telemetry([[:jibu, :request, :stop]])

    stream_stub(sse(@events))
    assert {:ok, _response} = Jibu.stream(client(__MODULE__), %{model: "m"}, fn _event -> :ok end)

    assert_received {[:jibu, :request, :stop], ^ref, _measurements, %{status: 200} = stop}
    assert stop.usage == %{"input_tokens" => 10, "output_tokens" => 5}
  end

  # A Req adapter that streams the test's events, then fails like a closed connection.
  # It runs in the test process, so it reads the events from the process dictionary.
  defmodule ClosingAdapter do
    @moduledoc false

    def run(request) do
      send(self(), :attempt)
      sse = Process.get(:closing_adapter_sse)
      response = Req.Response.new(status: 200, headers: [{"content-type", "text/event-stream"}])
      {:cont, {request, _response}} = request.into.({:data, sse}, {request, response})
      {request, %Req.TransportError{reason: :closed}}
    end
  end

  defp closing_adapter(events) do
    Process.put(:closing_adapter_sse, sse(events))
    ClosingAdapter
  end

  test "keeps the partial message when the connection closes during the stream" do
    client =
      Jibu.new(api_key: "sk-test", adapter: closing_adapter(Enum.take(@events, 4)), retry: false)

    assert {:error, %Error{type: "transport_error"} = error} =
             Jibu.stream(client, %{model: "m"}, fn _event -> :ok end)

    assert [%{"type" => "text", "text" => "Hel"}] = error.body["content"]
  end

  test "does not retry once events have arrived, also with a custom retry function" do
    for retry <- [&Jibu.Retry.retry/2, fn _request, _response -> true end] do
      adapter = closing_adapter(Enum.take(@events, 2))

      client =
        Jibu.new(
          api_key: "sk-test",
          adapter: adapter,
          retry: retry,
          retry_delay: 0,
          retry_log_level: false
        )

      assert {:error, %Error{type: "transport_error"}} =
               Jibu.stream(client, %{model: "m"}, forward())

      assert_received :attempt
      refute_received :attempt
      assert received_events() == Enum.take(@events, 2)
    end
  end

  test "returns an error for event data that is not JSON" do
    stream_stub(sse(Enum.take(@events, 1)) <> "event: broken\ndata: {nope\n\n")

    assert {:error, %Error{type: "invalid_json", status: 200}} =
             Jibu.stream(client(__MODULE__), %{model: "m"}, fn _event -> :ok end)
  end

  test "returns an error for a success response that is not an event stream" do
    Req.Test.expect(__MODULE__, &Req.Test.json(&1, %{"id" => "msg_1", "content" => []}))

    assert {:error, %Error{type: "invalid_stream", status: 200, body: %{"id" => "msg_1"}}} =
             Jibu.stream(client(__MODULE__), %{model: "m"}, forward())

    assert received_events() == []
  end
end
