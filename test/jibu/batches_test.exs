defmodule Jibu.BatchesTest do
  use ExUnit.Case, async: true

  import Jibu.TestHelpers

  alias Jibu.Batches
  alias Jibu.Error

  @batch %{
    "id" => "msgbatch_1",
    "type" => "message_batch",
    "processing_status" => "in_progress",
    "request_counts" => %{"processing" => 2}
  }

  test "create/2 posts the body unchanged" do
    capture(__MODULE__, @batch)

    body = %{
      requests: [
        %{custom_id: "a", params: %{model: "claude-opus-5-5", max_tokens: 10, messages: []}}
      ]
    }

    assert Batches.create(client(__MODULE__), body) == {:ok, @batch}
    assert_received {:request, conn, raw}
    assert {conn.method, conn.request_path} == {"POST", "/v1/messages/batches"}
    assert_sent_body(raw, body)
  end

  test "get/2, cancel/2 and delete/2 address one batch" do
    Req.Test.stub(__MODULE__, fn conn ->
      case {conn.method, conn.request_path} do
        {"GET", "/v1/messages/batches/msgbatch_1"} ->
          Req.Test.json(conn, @batch)

        {"POST", "/v1/messages/batches/msgbatch_1/cancel"} ->
          Req.Test.json(conn, %{@batch | "processing_status" => "canceling"})

        {"DELETE", "/v1/messages/batches/msgbatch_1"} ->
          Req.Test.json(conn, %{"id" => "msgbatch_1", "type" => "message_batch_deleted"})
      end
    end)

    client = client(__MODULE__)
    assert Batches.get(client, "msgbatch_1") == {:ok, @batch}
    assert {:ok, %{"processing_status" => "canceling"}} = Batches.cancel(client, "msgbatch_1")
    assert {:ok, %{"type" => "message_batch_deleted"}} = Batches.delete(client, "msgbatch_1")
  end

  test "list/2 and stream/2 read /v1/messages/batches" do
    capture(__MODULE__, %{"data" => [@batch], "has_more" => false})

    assert {:ok, %{"data" => [@batch]}} = Batches.list(client(__MODULE__), limit: 1)
    assert client(__MODULE__) |> Batches.stream() |> Enum.to_list() == [@batch]
    assert_received {:request, %{request_path: "/v1/messages/batches"}, _raw}
  end

  test "results/2 decodes the JSONL lines in order and skips blank lines" do
    lines = [
      %{
        "custom_id" => "b",
        "result" => %{"type" => "succeeded", "message" => %{"id" => "msg_b"}}
      },
      %{"custom_id" => "a", "result" => %{"type" => "errored", "error" => %{"type" => "x"}}}
    ]

    capture(__MODULE__, fn conn ->
      Plug.Conn.send_resp(conn, 200, Enum.map_join(lines, "\n", &JSON.encode!/1) <> "\n\n")
    end)

    assert {:ok, results} = Batches.results(client(__MODULE__), "msgbatch_1")
    assert Enum.to_list(results) == lines
    assert_received {:request, %{request_path: "/v1/messages/batches/msgbatch_1/results"}, _raw}
  end

  test "results/2 returns a Jibu.Error while the batch is not finished" do
    Req.Test.stub(__MODULE__, &api_error(&1, 404, "not_found_error"))

    assert {:error, %Error{status: 404, type: "not_found_error"}} =
             Batches.results(client(__MODULE__), "msgbatch_1")
  end
end
