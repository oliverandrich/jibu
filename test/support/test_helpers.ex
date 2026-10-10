defmodule Jibu.TestHelpers do
  @moduledoc false

  import ExUnit.Assertions

  @doc "A client whose requests go to the `Req.Test` stub `name`. Retries are off by default."
  def client(name, opts \\ []) do
    Jibu.new(Keyword.merge([api_key: "sk-test", plug: {Req.Test, name}, retry: false], opts))
  end

  @doc "Answers with an API error body, its request id and the given extra headers."
  def api_error(conn, status, type, headers \\ []) do
    headers
    |> Enum.reduce(conn, fn {name, value}, conn ->
      Plug.Conn.put_resp_header(conn, name, value)
    end)
    |> Plug.Conn.put_resp_header("request-id", "req_123")
    |> Plug.Conn.put_status(status)
    |> Req.Test.json(%{
      "type" => "error",
      "error" => %{"type" => type, "message" => "#{type} happened"},
      "request_id" => "req_123"
    })
  end

  @doc """
  Stubs `name` to answer with `reply` and to send `{:request, conn, raw_body}` to the test process.
  `reply` is a JSON map or a function of the conn.
  """
  def capture(name, reply) do
    test_pid = self()

    Req.Test.stub(name, fn conn ->
      send(test_pid, {:request, conn, Req.Test.raw_body(conn)})
      if is_function(reply, 1), do: reply.(conn), else: Req.Test.json(conn, reply)
    end)
  end

  @doc """
  Forwards the telemetry `events` of the calling process as `{event, ref, measurements, metadata}`.
  Other async tests emit the same events, so other processes are ignored. Returns `ref`.
  """
  def attach_telemetry(events) do
    ref = make_ref()
    test_pid = self()

    handler = fn event, measurements, metadata, _config ->
      if self() == test_pid, do: send(test_pid, {event, ref, measurements, metadata})
    end

    :telemetry.attach_many(ref, events, handler, nil)
    ExUnit.Callbacks.on_exit(fn -> :telemetry.detach(ref) end)
    ref
  end

  @doc "Encodes events as a Server-Sent Events stream, named by their `type`."
  def sse(events) do
    for event <- events, into: "", do: "event: #{event["type"]}\ndata: #{JSON.encode!(event)}\n\n"
  end

  @doc """
  The stream events that deliver `message`. Text arrives as one delta, tool input as one JSON delta.
  A string input is sent as raw JSON, so it may be invalid.
  """
  def stream_events(message) do
    blocks =
      message
      |> Map.get("content", [])
      |> Enum.with_index()
      |> Enum.flat_map(fn {block, index} -> block_events(block, index) end)

    start = Map.merge(message, %{"content" => [], "stop_reason" => nil})

    [%{"type" => "message_start", "message" => start}] ++
      blocks ++
      [
        %{"type" => "message_delta", "delta" => %{"stop_reason" => message["stop_reason"]}},
        %{"type" => "message_stop"}
      ]
  end

  defp block_events(%{"type" => "text", "text" => text} = block, index) do
    [
      %{
        "type" => "content_block_start",
        "index" => index,
        "content_block" => %{block | "text" => ""}
      },
      %{
        "type" => "content_block_delta",
        "index" => index,
        "delta" => %{"type" => "text_delta", "text" => text}
      },
      %{"type" => "content_block_stop", "index" => index}
    ]
  end

  defp block_events(%{"input" => input} = block, index) do
    json = if is_binary(input), do: input, else: JSON.encode!(input)

    [
      %{
        "type" => "content_block_start",
        "index" => index,
        "content_block" => %{block | "input" => %{}}
      },
      %{
        "type" => "content_block_delta",
        "index" => index,
        "delta" => %{"type" => "input_json_delta", "partial_json" => json}
      },
      %{"type" => "content_block_stop", "index" => index}
    ]
  end

  defp block_events(block, index) do
    [
      %{"type" => "content_block_start", "index" => index, "content_block" => block},
      %{"type" => "content_block_stop", "index" => index}
    ]
  end

  @doc "Answers `conn` with `events` as an event stream."
  def send_sse(conn, events) do
    conn
    |> Plug.Conn.put_resp_content_type("text/event-stream")
    |> Plug.Conn.send_resp(200, sse(events))
  end

  @doc "Asserts that the raw request body is the JSON encoding of `body`."
  def assert_sent_body(raw, body),
    do: assert(JSON.decode!(raw) == JSON.decode!(JSON.encode!(body)))
end
