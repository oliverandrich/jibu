defmodule JibuTest do
  use ExUnit.Case, async: true

  import Jibu.TestHelpers

  alias Jibu.Error
  alias Jibu.Response

  @message %{
    "id" => "msg_01",
    "type" => "message",
    "role" => "assistant",
    "model" => "claude-opus-5-5",
    "content" => [%{"type" => "text", "text" => "Hello"}],
    "stop_reason" => "end_turn",
    "usage" => %{"input_tokens" => 12, "output_tokens" => 3, "cache_read_input_tokens" => 8}
  }

  # Retries on, without waiting and without log output.
  defp retrying_client,
    do: client(__MODULE__, retry: &Jibu.Retry.retry/2, retry_delay: 0, retry_log_level: false)

  test "new/1 raises for an empty api key" do
    assert_raise ArgumentError, ~r/ANTHROPIC_API_KEY/, fn -> Jibu.new(api_key: "") end
  end

  describe "messages/2" do
    test "posts the body unchanged with the API headers and the caller's headers" do
      capture(__MODULE__, @message)

      body = %{
        model: "claude-opus-5-5",
        max_tokens: 1024,
        messages: [%{role: "user", content: "Hi"}],
        output_config: %{effort: "low"},
        some_future_field: %{nested: [1, 2]}
      }

      client = client(__MODULE__, betas: ["a-2026", "b-2026"], headers: [{"x-trace", "abc"}])
      assert {:ok, %Response{}} = Jibu.messages(client, body)

      assert_received {:request, conn, raw}
      assert {conn.method, conn.request_path} == {"POST", "/v1/messages"}
      assert_sent_body(raw, body)
      assert {"x-api-key", "sk-test"} in conn.req_headers
      assert {"anthropic-version", "2023-06-01"} in conn.req_headers
      assert {"anthropic-beta", "a-2026,b-2026"} in conn.req_headers
      assert {"x-trace", "abc"} in conn.req_headers
    end

    test "returns the response fields and the raw body" do
      Req.Test.stub(__MODULE__, &Req.Test.json(&1, @message))

      assert {:ok, response} = Jibu.messages(client(__MODULE__), %{model: "claude-opus-5-5"})
      assert response.id == "msg_01"
      assert response.model == "claude-opus-5-5"
      assert response.stop_reason == "end_turn"
      assert response.content == @message["content"]
      assert response.usage == @message["usage"]
      assert response.body == @message
    end

    test "turns an API error into a Jibu.Error without retrying" do
      Req.Test.expect(__MODULE__, &api_error(&1, 400, "invalid_request_error"))

      assert {:error, %Error{} = error} = Jibu.messages(retrying_client(), %{})
      assert error.status == 400
      assert error.type == "invalid_request_error"
      assert error.message == "invalid_request_error happened"
      assert error.request_id == "req_123"
    end

    test "retries overloaded and conflict responses and honours retry-after" do
      Req.Test.expect(__MODULE__, &api_error(&1, 529, "overloaded_error", [{"retry-after", "0"}]))
      Req.Test.expect(__MODULE__, &api_error(&1, 409, "conflict_error"))
      Req.Test.expect(__MODULE__, &Req.Test.json(&1, @message))

      assert {:ok, %Response{}} = Jibu.messages(retrying_client(), %{})
      Req.Test.verify!(__MODULE__)
    end

    test "retries any 5xx status" do
      Req.Test.expect(__MODULE__, &api_error(&1, 520, "api_error"))
      Req.Test.expect(__MODULE__, &Req.Test.json(&1, @message))

      assert {:ok, %Response{}} = Jibu.messages(retrying_client(), %{})
      Req.Test.verify!(__MODULE__)
    end

    test "does not retry when the API says x-should-retry false" do
      Req.Test.expect(__MODULE__, &api_error(&1, 500, "api_error", [{"x-should-retry", "false"}]))

      assert {:error, %Error{status: 500}} = Jibu.messages(retrying_client(), %{})
    end

    test "reports retry-after in milliseconds" do
      Req.Test.stub(__MODULE__, &api_error(&1, 429, "rate_limit_error", [{"retry-after", "7"}]))

      assert {:error, %Error{status: 429, retry_after: 7000}} =
               Jibu.messages(client(__MODULE__), %{})
    end

    test "turns a transport failure into a Jibu.Error" do
      Req.Test.stub(__MODULE__, &Req.Test.transport_error(&1, :econnrefused))

      assert {:error, %Error{type: "transport_error", status: nil} = error} =
               Jibu.messages(client(__MODULE__), %{})

      assert %Req.TransportError{reason: :econnrefused} = error.reason
    end

    test "emits a telemetry span with model, status and usage" do
      ref =
        :telemetry_test.attach_event_handlers(self(), [
          [:jibu, :request, :start],
          [:jibu, :request, :stop]
        ])

      Req.Test.stub(__MODULE__, &Req.Test.json(&1, @message))

      Jibu.messages(client(__MODULE__), %{model: "claude-opus-5-5"})

      assert_received {[:jibu, :request, :start], ^ref, _measurements, start}
      assert start.path == "/v1/messages"
      assert start.model == "claude-opus-5-5"
      assert_received {[:jibu, :request, :stop], ^ref, _measurements, stop}
      assert stop.status == 200
      assert stop.usage == @message["usage"]
    end
  end

  test "count_tokens/2 posts the body unchanged and returns the API's answer" do
    capture(__MODULE__, %{"input_tokens" => 42})
    body = %{model: "claude-opus-5-5", messages: [%{role: "user", content: "Hi"}]}

    assert Jibu.count_tokens(client(__MODULE__), body) == {:ok, %{"input_tokens" => 42}}
    assert_received {:request, conn, raw}
    assert {conn.method, conn.request_path} == {"POST", "/v1/messages/count_tokens"}
    assert_sent_body(raw, body)
  end
end
