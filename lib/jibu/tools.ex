defmodule Jibu.Tools do
  @moduledoc """
  Runs a tool-use conversation until the model stops asking for tools.

  Jibu executes every tool in `body.tools` that carries a `:run` function.
  Jibu removes `:run` before sending. Every other field passes through.
  Tools without `:run`, such as server tools, go out unchanged.

      weather = %{
        name: "weather",
        description: "Current weather for a city",
        input_schema: %{type: "object", properties: %{city: %{type: "string"}}, required: ["city"]},
        run: fn %{"city" => city} -> {:ok, "sunny in " <> city} end
      }

      {:ok, response, messages} =
        Jibu.Tools.run(client, %{
          model: "claude-opus-5-5",
          max_tokens: 1024,
          tools: [weather],
          messages: [%{role: "user", content: "Weather in Berlin?"}]
        })

  `:run` receives the tool input as a map with string keys.
  It returns `{:ok, content}` or `{:error, content}`.
  `content` is a string or a list of content blocks.

  An error tuple, a raised exception or an unknown tool name becomes a `tool_result` with
  `is_error: true`. The model sees the error and can react.
  All results of one turn go back in a single user message.

  A `pause_turn` response goes back unchanged, so the model can continue.
  The returned `messages` hold the whole conversation, ending with the final assistant turn.

  See the [Tools guide](tools.md) for more.
  """

  alias Jibu.Body
  alias Jibu.Error
  alias Jibu.Prompt
  alias Jibu.Response

  @doc """
  Runs the loop.

  The second argument is a request body or a prompt. A prompt takes the shortcuts of
  `Jibu.ask/3`, and `tools:` goes into the body like any other keyword.

  Returns `{:ok, response, messages}` for the first response whose `stop_reason` is neither
  `"tool_use"` nor `"pause_turn"`. Check that `stop_reason` for `"refusal"` or `"max_tokens"`
  before using the answer.

  ## Options

    * `:max_iterations` - maximum number of requests, default `10`.
    * `:max_concurrency` - maximum number of tools of one turn that run at once, default `1`.
      Above `1`, each tool runs in its own task without a timeout.
  """
  @spec run(Req.Request.t(), map() | String.t() | [map()], keyword()) ::
          {:ok, Response.t(), [map()]} | {:error, Error.t()}
  def run(client, body_or_prompt, opts \\ [])

  def run(client, prompt, opts) when is_binary(prompt) or is_list(prompt) do
    if prompt != [] and Keyword.keyword?(prompt) do
      raise ArgumentError, "pass a request body as a map, not a keyword list"
    end

    {loop_opts, prompt_opts} = Keyword.split(opts, [:max_iterations, :max_concurrency])
    run(client, Prompt.body(prompt, prompt_opts), loop_opts)
  end

  def run(client, body, opts) when is_map(body) do
    {tools_key, tools} = Body.fetch(body, :tools, [])
    {messages_key, messages} = Body.fetch(body, :messages, [])

    runners =
      for tool <- tools, run = Body.get(tool, :run), into: %{}, do: {Body.get(tool, :name), run}

    body =
      if tools == [],
        do: body,
        else: Map.put(body, tools_key, Enum.map(tools, &Map.drop(&1, [:run, "run"])))

    send = fn messages -> Jibu.messages(client, Map.put(body, messages_key, messages)) end
    execute = executor(runners, Keyword.get(opts, :max_concurrency, 1))
    loop(send, execute, messages, Keyword.get(opts, :max_iterations, 10))
  end

  defp loop(_send, _execute, _messages, 0), do: max_iterations()

  defp loop(send, execute, messages, left) do
    with {:ok, response} <- send.(messages) do
      messages = messages ++ [%{role: "assistant", content: response.content}]
      continue(response, send, execute, messages, left - 1)
    end
  end

  # With no request left, tools do not run: their results could never be sent.
  defp continue(%Response{stop_reason: reason}, _send, _execute, _messages, 0)
       when reason in ["tool_use", "pause_turn"],
       do: max_iterations()

  defp continue(%Response{stop_reason: "tool_use"} = response, send, execute, messages, left) do
    results = execute.(for %{"type" => "tool_use"} = call <- response.content, do: call)
    loop(send, execute, messages ++ [%{role: "user", content: results}], left)
  end

  defp continue(%Response{stop_reason: "pause_turn"}, send, execute, messages, left),
    do: loop(send, execute, messages, left)

  defp continue(response, _send, _execute, messages, _left), do: {:ok, response, messages}

  defp max_iterations do
    {:error, %Error{type: "max_iterations", message: "the tool loop reached :max_iterations"}}
  end

  # Without concurrency, tools run in the caller and share its process.
  defp executor(runners, 1),
    do: &Enum.map(&1, fn call -> result(call, outcome(call, runners)) end)

  defp executor(runners, max_concurrency)
       when is_integer(max_concurrency) and max_concurrency > 1 do
    fn calls ->
      calls
      |> Task.async_stream(&outcome(&1, runners),
        max_concurrency: max_concurrency,
        timeout: :infinity
      )
      |> Enum.zip_with(calls, fn {:ok, outcome}, call -> result(call, outcome) end)
    end
  end

  defp outcome(%{"name" => name, "input" => input}, runners) do
    case Map.fetch(runners, name) do
      {:ok, run} -> invoke(run, input)
      :error -> {:error, "unknown tool: #{name}"}
    end
  end

  # A tool's exception goes back to the model as an error result instead of ending the loop.
  defp invoke(run, input) do
    run.(input)
  rescue
    exception -> {:error, Exception.message(exception)}
  end

  defp result(%{"id" => id}, {:ok, content}),
    do: %{type: "tool_result", tool_use_id: id, content: content}

  defp result(%{"id" => id}, {:error, content}),
    do: %{type: "tool_result", tool_use_id: id, content: content, is_error: true}

  defp result(_call, other) do
    raise ArgumentError,
          "a tool's :run must return {:ok, content} or {:error, content}, got: #{inspect(other)}"
  end
end
