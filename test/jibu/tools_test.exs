defmodule Jibu.ToolsTest do
  use ExUnit.Case, async: true

  import Jibu.TestHelpers

  alias Jibu.Error
  alias Jibu.Response
  alias Jibu.Tools

  defp tool_use(id, name, input),
    do: %{"type" => "tool_use", "id" => id, "name" => name, "input" => input}

  defp reply(content, stop_reason), do: %{"content" => content, "stop_reason" => stop_reason}

  # Answers each request with the next reply and reports every decoded request body.
  # `respond` sends a reply as JSON or as an event stream.
  defp script(replies, respond \\ &Req.Test.json/2) do
    test_pid = self()

    for reply <- replies do
      Req.Test.expect(__MODULE__, fn conn ->
        send(test_pid, {:body, JSON.decode!(Req.Test.raw_body(conn))})
        respond.(conn, reply)
      end)
    end
  end

  defp stream_script(replies), do: script(replies, &respond_stream/2)

  defp respond_stream(conn, reply) do
    conn
    |> Plug.Conn.put_resp_content_type("text/event-stream")
    |> Plug.Conn.send_resp(200, sse(stream_events(reply)))
  end

  defp forward do
    test_pid = self()
    fn event -> send(test_pid, {:event, event}) end
  end

  defp received_event_types(acc \\ []) do
    receive do
      {:event, %{"type" => type}} -> received_event_types([type | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  # The tool results of the second request.
  defp sent_results do
    assert_received {:body, _first}
    assert_received {:body, second}
    List.last(second["messages"])["content"]
  end

  defp weather_tool(run) do
    %{
      name: "weather",
      description: "Current weather",
      input_schema: %{type: "object"},
      strict: true,
      run: run
    }
  end

  test "runs the requested tools and returns all results in one user message" do
    first = [
      %{"type" => "text", "text" => "Checking"},
      tool_use("t1", "weather", %{"city" => "Berlin"}),
      tool_use("t2", "weather", %{"city" => "Rom"})
    ]

    script([reply(first, "tool_use"), reply([%{"type" => "text", "text" => "Done"}], "end_turn")])
    tool = weather_tool(fn %{"city" => city} -> {:ok, "sunny in #{city}"} end)

    body = %{
      model: "m",
      max_tokens: 100,
      tools: [tool],
      messages: [%{role: "user", content: "Weather?"}]
    }

    assert {:ok, %Response{stop_reason: "end_turn"} = response, messages} =
             Tools.run(client(__MODULE__), body)

    assert Response.text(response) == "Done"

    assert_received {:body, sent}

    assert sent["tools"] == [
             %{
               "name" => "weather",
               "description" => "Current weather",
               "input_schema" => %{"type" => "object"},
               "strict" => true
             }
           ]

    assert_received {:body, second}
    assert [_user, assistant, results] = second["messages"]
    assert assistant == %{"role" => "assistant", "content" => first}

    assert results == %{
             "role" => "user",
             "content" => [
               %{"type" => "tool_result", "tool_use_id" => "t1", "content" => "sunny in Berlin"},
               %{"type" => "tool_result", "tool_use_id" => "t2", "content" => "sunny in Rom"}
             ]
           }

    assert List.last(messages) == %{role: "assistant", content: response.content}
    assert length(messages) == 4
  end

  # A tool that sleeps for the milliseconds in its `delay` input.
  defp delay_tool do
    weather_tool(fn %{"delay" => delay} ->
      Process.sleep(delay)
      {:ok, "waited #{delay}"}
    end)
  end

  # A tool that waits up to one second for `count` tools to start. Run alone, it reports an error.
  defp barrier_tool(count) do
    started = :counters.new(1, [])

    weather_tool(fn _input ->
      :counters.add(started, 1, 1)
      deadline = System.monotonic_time(:millisecond) + 1000
      await_barrier(started, count, deadline)
    end)
  end

  defp await_barrier(started, count, deadline) do
    cond do
      :counters.get(started, 1) >= count ->
        {:ok, "together"}

      System.monotonic_time(:millisecond) > deadline ->
        {:error, "alone"}

      true ->
        Process.sleep(5)
        await_barrier(started, count, deadline)
    end
  end

  test "runs tools one after another in the calling process by default" do
    test_pid = self()
    calls = [tool_use("t1", "weather", %{}), tool_use("t2", "weather", %{})]
    script([reply(calls, "tool_use"), reply([], "end_turn")])

    tool = weather_tool(fn _input -> {:ok, inspect(self() == test_pid)} end)
    body = %{tools: [tool], messages: [%{role: "user", content: "x"}]}

    assert {:ok, _response, _messages} = Tools.run(client(__MODULE__), body)

    assert [%{"content" => "true"}, %{"content" => "true"}] = sent_results()
  end

  test "runs the tools of one turn concurrently with max_concurrency" do
    calls = [tool_use("t1", "weather", %{}), tool_use("t2", "weather", %{})]
    script([reply(calls, "tool_use"), reply([], "end_turn")])

    body = %{tools: [barrier_tool(2)], messages: [%{role: "user", content: "x"}]}

    assert {:ok, _response, _messages} =
             Tools.run(client(__MODULE__), body, max_concurrency: 2)

    assert [
             %{"tool_use_id" => "t1", "content" => "together"},
             %{"tool_use_id" => "t2", "content" => "together"}
           ] = sent_results()
  end

  test "rejects an invalid max_concurrency or tool_timeout before the first request" do
    body = %{tools: [weather_tool(fn _input -> {:ok, "x"} end)], messages: []}

    for opts <- [[max_concurrency: 0], [tool_timeout: 0]] do
      assert_raise FunctionClauseError, fn -> Tools.run(client(__MODULE__), body, opts) end
    end

    refute_received {:body, _}
  end

  test "a prompt takes max_concurrency and tool_timeout as loop options" do
    calls = [tool_use("t1", "weather", %{}), tool_use("t2", "weather", %{})]
    script([reply(calls, "tool_use"), reply([], "end_turn")])

    assert {:ok, _response, _messages} =
             Tools.run(client(__MODULE__), "x",
               tools: [barrier_tool(2)],
               max_concurrency: 2,
               tool_timeout: 5000
             )

    assert_received {:body, first}
    refute Map.has_key?(first, "max_concurrency")
    refute Map.has_key?(first, "tool_timeout")
    assert_received {:body, second}

    assert [%{"content" => "together"}, %{"content" => "together"}] =
             List.last(second["messages"])["content"]
  end

  test "keeps the order of tool calls when a later tool finishes first" do
    calls = [
      tool_use("t1", "weather", %{"delay" => 50}),
      tool_use("t2", "weather", %{"delay" => 0})
    ]

    script([reply(calls, "tool_use"), reply([], "end_turn")])

    body = %{tools: [delay_tool()], messages: [%{role: "user", content: "x"}]}

    assert {:ok, _response, _messages} =
             Tools.run(client(__MODULE__), body, max_concurrency: 2)

    assert [
             %{"tool_use_id" => "t1", "content" => "waited 50"},
             %{"tool_use_id" => "t2", "content" => "waited 0"}
           ] = sent_results()
  end

  test "a tool that exceeds tool_timeout returns an error result" do
    calls = [
      tool_use("t1", "weather", %{"delay" => 500}),
      tool_use("t2", "weather", %{"delay" => 0})
    ]

    body = %{tools: [delay_tool()], messages: [%{role: "user", content: "x"}]}

    for max_concurrency <- [1, 2] do
      script([reply(calls, "tool_use"), reply([], "end_turn")])

      assert {:ok, _response, _messages} =
               Tools.run(client(__MODULE__), body,
                 tool_timeout: 50,
                 max_concurrency: max_concurrency
               )

      assert [
               %{
                 "tool_use_id" => "t1",
                 "is_error" => true,
                 "content" => "tool timed out after 50 ms"
               },
               %{"tool_use_id" => "t2", "content" => "waited 0"}
             ] = sent_results()
    end
  end

  test "a tool's exit reaches a caller that traps exits" do
    Process.flag(:trap_exit, true)
    script([reply([tool_use("t1", "weather", %{})], "tool_use")])
    body = %{tools: [weather_tool(fn _input -> exit(:boom) end)], messages: []}

    assert catch_exit(Tools.run(client(__MODULE__), body, tool_timeout: 1000)) == :boom
  end

  test "tool_timeout limits each tool, not the whole turn" do
    calls = [
      tool_use("t1", "weather", %{"delay" => 300}),
      tool_use("t2", "weather", %{"delay" => 300})
    ]

    script([reply(calls, "tool_use"), reply([], "end_turn")])
    body = %{tools: [delay_tool()], messages: [%{role: "user", content: "x"}]}

    assert {:ok, _response, _messages} = Tools.run(client(__MODULE__), body, tool_timeout: 500)
    assert [%{"content" => "waited 300"}, %{"content" => "waited 300"}] = sent_results()
  end

  test "tool_timeout runs tools outside the calling process" do
    test_pid = self()
    script([reply([tool_use("t1", "weather", %{})], "tool_use"), reply([], "end_turn")])

    tool = weather_tool(fn _input -> {:ok, inspect(self() == test_pid)} end)
    body = %{tools: [tool], messages: [%{role: "user", content: "x"}]}

    assert {:ok, _response, _messages} = Tools.run(client(__MODULE__), body, tool_timeout: 1000)
    assert [%{"content" => "false"}] = sent_results()
  end

  test "on_event streams every turn and passes the events of all turns" do
    first = [
      %{"type" => "text", "text" => "Checking"},
      tool_use("t1", "weather", %{"city" => "Rom"})
    ]

    stream_script([
      reply(first, "tool_use"),
      reply([%{"type" => "text", "text" => "Done"}], "end_turn")
    ])

    tool = weather_tool(fn %{"city" => city} -> {:ok, "sunny in #{city}"} end)
    body = %{tools: [tool], messages: [%{role: "user", content: "Weather?"}]}

    assert {:ok, response, messages} = Tools.run(client(__MODULE__), body, on_event: forward())
    assert Response.text(response) == "Done"
    assert length(messages) == 4

    assert_received {:body, %{"stream" => true}}
    assert_received {:body, %{"stream" => true} = second}
    assert [_user, %{"content" => ^first}, results] = second["messages"]
    assert [%{"tool_use_id" => "t1", "content" => "sunny in Rom"}] = results["content"]

    types = received_event_types()
    assert Enum.count(types, &(&1 == "message_start")) == 2
    assert List.last(types) == "message_stop"
  end

  test "a prompt takes on_event as a loop option" do
    stream_script([reply([%{"type" => "text", "text" => "Hi"}], "end_turn")])

    assert {:ok, _response, _messages} =
             Tools.run(client(__MODULE__), "x", tools: [], on_event: fn _event -> :ok end)

    assert_received {:body, first}
    assert first["stream"] == true
    refute Map.has_key?(first, "on_event")
  end

  test "a tool input that is not valid JSON returns an error result without running the tool" do
    test_pid = self()

    calls = [
      tool_use("t1", "weather", ~s({"city": "Ber)),
      tool_use("t2", "missing", ~s({"city": "Ber))
    ]

    stream_script([reply(calls, "tool_use"), reply([], "end_turn")])

    tool =
      weather_tool(fn _input ->
        send(test_pid, :ran)
        {:ok, "x"}
      end)

    body = %{tools: [tool], messages: [%{role: "user", content: "x"}]}

    assert {:ok, _response, _messages} =
             Tools.run(client(__MODULE__), body, on_event: fn _event -> :ok end)

    assert_received {:body, _first}
    assert_received {:body, second}
    assert [_user, %{"content" => assistant}, %{"content" => results}] = second["messages"]

    # The API requires an object as tool input, so the replayed turn carries an empty one.
    assert [%{"id" => "t1", "input" => %{}}, %{"id" => "t2", "input" => %{}}] = assistant

    assert [
             %{
               "tool_use_id" => "t1",
               "is_error" => true,
               "content" => "the tool input is not valid JSON"
             },
             %{"tool_use_id" => "t2", "is_error" => true, "content" => "unknown tool: missing"}
           ] = results

    refute_received :ran
  end

  test "on_event: nil sends the turns without streaming" do
    script([reply([%{"type" => "text", "text" => "Hi"}], "end_turn")])

    assert {:ok, response, _messages} =
             Tools.run(client(__MODULE__), %{messages: []}, on_event: nil)

    assert Response.text(response) == "Hi"
    assert_received {:body, first}
    refute Map.has_key?(first, "stream")
  end

  test "a failing, raising or unknown tool returns an error result to the model" do
    script([
      reply(
        [
          tool_use("t1", "weather", %{}),
          tool_use("t2", "crash", %{}),
          tool_use("t3", "missing", %{})
        ],
        "tool_use"
      ),
      reply([], "end_turn")
    ])

    tools = [
      weather_tool(fn _input -> {:error, "service down"} end),
      %{name: "crash", input_schema: %{type: "object"}, run: fn _input -> raise "boom" end}
    ]

    assert {:ok, _response, _messages} =
             Tools.run(client(__MODULE__), %{
               tools: tools,
               messages: [%{role: "user", content: "x"}]
             })

    assert [
             %{"tool_use_id" => "t1", "is_error" => true, "content" => "service down"},
             %{"tool_use_id" => "t2", "is_error" => true, "content" => "boom"},
             %{"tool_use_id" => "t3", "is_error" => true, "content" => "unknown tool: missing"}
           ] = sent_results()
  end

  test "resends after pause_turn without adding a user message" do
    paused = [
      %{"type" => "server_tool_use", "id" => "s1", "name" => "web_search", "input" => %{}}
    ]

    script([reply(paused, "pause_turn"), reply([], "end_turn")])

    body = %{
      tools: [%{type: "web_search_20260209", name: "web_search"}],
      messages: [%{role: "user", content: "x"}]
    }

    assert {:ok, %Response{stop_reason: "end_turn"}, _messages} =
             Tools.run(client(__MODULE__), body)

    assert_received {:body, _first}
    assert_received {:body, second}
    assert [_user, %{"role" => "assistant", "content" => ^paused}] = second["messages"]
  end

  test "stops with an error after max_iterations" do
    loop = reply([tool_use("t1", "weather", %{})], "tool_use")
    script([loop, loop, loop])

    body = %{
      tools: [weather_tool(fn _input -> {:ok, "x"} end)],
      messages: [%{role: "user", content: "x"}]
    }

    assert {:error, %Error{type: "max_iterations"}} =
             Tools.run(client(__MODULE__), body, max_iterations: 2)
  end

  test "does not run tools whose results the iteration cap would discard" do
    test_pid = self()
    script([reply([tool_use("t1", "weather", %{})], "tool_use")])

    body = %{
      tools: [
        weather_tool(fn _input ->
          send(test_pid, :ran)
          {:ok, "x"}
        end)
      ],
      messages: [%{role: "user", content: "x"}]
    }

    assert {:error, %Error{type: "max_iterations"}} =
             Tools.run(client(__MODULE__), body, max_iterations: 1)

    refute_received :ran
  end

  test "accepts string keys in the body" do
    script([reply([tool_use("t1", "weather", %{})], "tool_use"), reply([], "end_turn")])

    body = %{
      "tools" => [
        %{"name" => "weather", "input_schema" => %{}, "run" => fn _input -> {:ok, "x"} end}
      ],
      "messages" => [%{"role" => "user", "content" => "x"}]
    }

    assert {:ok, _response, messages} = Tools.run(client(__MODULE__), body)
    assert length(messages) == 4
    assert_received {:body, first}
    assert first["tools"] == [%{"name" => "weather", "input_schema" => %{}}]
  end
end
