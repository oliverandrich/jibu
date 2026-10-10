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
  defp script(replies) do
    test_pid = self()

    for reply <- replies do
      Req.Test.expect(__MODULE__, fn conn ->
        send(test_pid, {:body, JSON.decode!(Req.Test.raw_body(conn))})
        Req.Test.json(conn, reply)
      end)
    end
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

    assert_received {:body, _first}
    assert_received {:body, second}

    assert [
             %{"tool_use_id" => "t1", "is_error" => true, "content" => "service down"},
             %{"tool_use_id" => "t2", "is_error" => true, "content" => "boom"},
             %{"tool_use_id" => "t3", "is_error" => true, "content" => "unknown tool: missing"}
           ] = List.last(second["messages"])["content"]
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
