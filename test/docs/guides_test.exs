defmodule Jibu.GuidesTest do
  # Runs every `elixir` block of the README and the guides, so the examples cannot rot.
  # Not async: `Req.default_options/1` and the working directory are global.
  use ExUnit.Case, async: false

  @moduletag :tmp_dir

  @guides ["README.md" | Path.wildcard("docs/*.md")]
  for guide <- @guides, do: @external_resource(guide)

  defmodule MyApp.Calendar do
    @moduledoc false
    def events_json(date), do: ~s([{"date": "#{date}", "subject": "Workshop"}])
  end

  setup %{tmp_dir: dir} do
    previous_defaults = Req.default_options()
    previous_key = System.get_env("ANTHROPIC_API_KEY")

    # Every client, including one built inside an example, goes to the stub.
    Req.default_options(plug: {Req.Test, __MODULE__}, retry: false)
    System.put_env("ANTHROPIC_API_KEY", "sk-test")
    Req.Test.set_req_test_to_shared()
    Req.Test.stub(__MODULE__, &respond/1)

    for name <- ~w(contract.pdf handbook.pdf), do: File.write!(Path.join(dir, name), "%PDF-1.7")
    File.write!(Path.join(dir, "scan.png"), <<137, 80, 78, 71>>)

    on_exit(fn ->
      Req.default_options(previous_defaults)
      restore_env("ANTHROPIC_API_KEY", previous_key)
      :telemetry.detach("jibu-usage")
    end)

    :ok
  end

  for guide <- @guides do
    test "the examples in #{guide} run", %{tmp_dir: dir} do
      blocks = blocks(unquote(guide))
      assert blocks != [], "no elixir blocks in #{unquote(guide)}"

      File.cd!(dir, fn ->
        Enum.reduce(blocks, bindings(), fn {code, line}, binding ->
          {_result, binding} =
            Code.eval_string(code, binding, file: unquote(guide), line: line)

          binding
        end)
      end)
    end
  end

  defp blocks(guide) do
    lines = guide |> File.read!() |> String.split("\n")

    {blocks, _state} =
      lines
      |> Enum.with_index(1)
      |> Enum.reduce({[], nil}, fn
        {"```elixir", number}, {blocks, nil} ->
          {blocks, {number + 1, []}}

        {"```", _number}, {blocks, {start, acc}} ->
          {[{acc |> Enum.reverse() |> Enum.join("\n"), start} | blocks], nil}

        {line, _number}, {blocks, {start, acc}} ->
          {blocks, {start, [line | acc]}}

        {_line, _number}, {blocks, nil} ->
          {blocks, nil}
      end)

    Enum.reverse(blocks)
  end

  # Values the examples use without defining them.
  defp bindings do
    [
      client: Jibu.new(),
      schema: %{type: "object", properties: %{project: %{type: "string"}}},
      messages: [%{role: "user", content: "Hi"}],
      body: %{
        model: "claude-opus-5-5",
        max_tokens: 64,
        messages: [%{role: "user", content: "Hi"}]
      },
      instructions: "Suggest bookings.",
      project_list: "P00-000000 Abschluss des Tages",
      todays_events: "09:00 Workshop",
      response: Jibu.Response.new(%{"usage" => %{"cache_read_input_tokens" => 10}}),
      days: [{"monday", "09:00 Workshop"}],
      image_id: "file_image",
      png_binary: <<137, 80, 78, 71>>,
      pdf_binary: "%PDF-1.7"
    ]
  end

  defp respond(conn) do
    {:ok, raw, conn} = Plug.Conn.read_body(conn)
    json? = Plug.Conn.get_req_header(conn, "content-type") == ["application/json"]
    body = if json?, do: JSON.decode!(raw), else: %{}
    route(conn, conn.method, conn.path_info, body)
  end

  defp route(conn, "POST", ["v1", "messages"], %{"stream" => true}) do
    %{"content" => [%{"text" => text}]} = message = text_message("Hello")

    events = [
      %{"type" => "message_start", "message" => %{message | "content" => []}},
      %{
        "type" => "content_block_start",
        "index" => 0,
        "content_block" => %{"type" => "text", "text" => ""}
      },
      %{
        "type" => "content_block_delta",
        "index" => 0,
        "delta" => %{"type" => "text_delta", "text" => text}
      },
      %{"type" => "content_block_stop", "index" => 0},
      %{"type" => "message_stop"}
    ]

    Jibu.TestHelpers.send_sse(conn, events)
  end

  defp route(conn, "POST", ["v1", "messages"], body), do: Req.Test.json(conn, message(body))

  defp route(conn, "POST", ["v1", "messages", "count_tokens"], _body),
    do: Req.Test.json(conn, %{"input_tokens" => 10})

  defp route(conn, "GET", ["v1", "models", id], _body), do: Req.Test.json(conn, %{"id" => id})

  defp route(conn, "GET", ["v1", "models"], _body),
    do: Req.Test.json(conn, %{"data" => [%{"id" => "claude-opus-5-5"}], "has_more" => false})

  defp route(conn, "POST", ["v1", "files"], _body), do: Req.Test.json(conn, %{"id" => "file_1"})

  defp route(conn, "GET", ["v1", "files"], _body),
    do: Req.Test.json(conn, %{"data" => [%{"id" => "file_1"}], "has_more" => false})

  defp route(conn, method, ["v1", "files", id], _body) when method in ["GET", "DELETE"],
    do: Req.Test.json(conn, %{"id" => id})

  defp route(conn, "POST", ["v1", "messages", "batches"], _body),
    do: Req.Test.json(conn, %{"id" => "msgbatch_1", "processing_status" => "in_progress"})

  defp route(conn, "GET", ["v1", "messages", "batches", _id, "results"], _body) do
    line = %{
      "custom_id" => "monday",
      "result" => %{"type" => "succeeded", "message" => message(%{})}
    }

    Plug.Conn.send_resp(conn, 200, JSON.encode!(line) <> "\n")
  end

  defp route(conn, _method, ["v1", "messages", "batches", id | _action], _body),
    do: Req.Test.json(conn, %{"id" => id, "processing_status" => "ended"})

  # Asks for the first tool once, then answers. Structured output gets a matching JSON text.
  defp message(%{"tools" => [%{"name" => name} | _rest], "messages" => messages}) do
    if Enum.any?(messages, &tool_results?/1),
      do: text_message("Done"),
      else: %{
        "content" => [
          %{
            "type" => "tool_use",
            "id" => "t1",
            "name" => name,
            "input" => %{"date" => "2026-10-12"}
          }
        ],
        "stop_reason" => "tool_use"
      }
  end

  defp message(%{"output_config" => %{"format" => _format}}),
    do: text_message(~s({"project": "P00-000000", "hours": 2.5, "text": "Workshop"}))

  defp message(_body), do: text_message("Hello")

  defp text_message(text) do
    %{
      "content" => [%{"type" => "text", "text" => text}],
      "stop_reason" => "end_turn",
      "usage" => %{"input_tokens" => 10, "output_tokens" => 5}
    }
  end

  defp tool_results?(%{"content" => [%{"type" => "tool_result"} | _rest]}), do: true
  defp tool_results?(_message), do: false

  defp restore_env(name, nil), do: System.delete_env(name)
  defp restore_env(name, value), do: System.put_env(name, value)
end
