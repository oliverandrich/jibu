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

  @doc "Asserts that the raw request body is the JSON encoding of `body`."
  def assert_sent_body(raw, body),
    do: assert(JSON.decode!(raw) == JSON.decode!(JSON.encode!(body)))
end
