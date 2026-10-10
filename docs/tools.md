# Tools

`Jibu.Tools.run/3` runs a conversation in which the model calls your functions.

## Define a tool

A tool is the map the API expects, plus a `:run` function.

```elixir
calendar = %{
  name: "calendar_events",
  description: "Lists the user's calendar events for one day",
  input_schema: %{
    type: "object",
    properties: %{date: %{type: "string", format: "date"}},
    required: ["date"],
    additionalProperties: false
  },
  strict: true,
  run: fn %{"date" => date} -> {:ok, MyApp.Calendar.events_json(date)} end
}
```

`:run` receives the input as a map with string keys.
It returns `{:ok, content}` or `{:error, content}`.
`content` is a string or a list of content blocks.

## Run the loop

```elixir
{:ok, response, messages} =
  Jibu.Tools.run(client, %{
    model: "claude-opus-5-5",
    max_tokens: 2048,
    tools: [calendar],
    messages: [%{role: "user", content: "What did I do on Monday?"}]
  })
```

A prompt works as well, with the shortcuts of `Jibu.ask/3`:

```elixir
{:ok, response, messages} =
  Jibu.Tools.run(client, "What did I do on Monday?", tools: [calendar], effort: :low)
```

The loop sends the request and runs every requested tool.
It returns all results of one turn in a single user message.
It repeats until `stop_reason` is neither `"tool_use"` nor `"pause_turn"`.

`messages` holds the whole conversation, ending with the final assistant turn.
Append the next user message to continue.

## Errors in tools

An error tuple, a raised exception or an unknown tool name becomes a result with `is_error: true`.
The model sees the error message and can react.
Exits and throws are not caught.

## Limits

`:max_iterations` caps the number of requests. The default is `10`.

```elixir
Jibu.Tools.run(client, body, max_iterations: 4)
```

Reaching the cap returns `{:error, %Jibu.Error{type: "max_iterations"}}`.

## Errors in the loop

Every error of `run/3` carries the conversation so far in `error.messages`.

After a failed request, `messages` is the conversation that request sent.
This holds for API errors, transport errors and stream errors.
Pass it as the body's `messages` to send that request again.
The new call starts with a fresh `:max_iterations`.

```elixir
case Jibu.Tools.run(client, body) do
  {:ok, response, messages} -> {response, messages}
  {:error, %Jibu.Error{type: "overloaded_error", messages: messages}} -> Jibu.Tools.run(client, %{body | messages: messages})
  {:error, error} -> raise error
end
```

After `"max_iterations"`, `messages` ends with the last assistant turn.
If that turn asks for tools, they did not run, and the conversation does not resume as it is.
If it is a `pause_turn`, sending the conversation again continues the turn.

## Concurrency

The tools of one turn run one after another in the calling process by default.
`:max_concurrency` runs up to that many at once.

```elixir
Jibu.Tools.run(client, body, max_concurrency: 4)
```

Each tool then runs in its own task, so `self()` and the process dictionary differ from the caller.
Tools may start and finish in any order. Their results keep the order of the tool calls.
An exit or throw in a tool crashes the caller.

## Timeouts

Tools run without a time limit by default.
`:tool_timeout` limits each tool to that many milliseconds.

```elixir
Jibu.Tools.run(client, body, tool_timeout: 5_000)
```

A tool that exceeds it is killed and returns `"tool timed out after 5000 ms"` with `is_error: true`.
Side effects it started may be left incomplete.
A finite timeout runs each tool in its own task, also with `max_concurrency: 1`.
The notes under [Concurrency](#concurrency) on processes, exits and throws then apply.

## Streaming

`:on_event` streams every turn through `Jibu.stream/3`.
The function receives all events of all turns in order. Each turn starts with its own `message_start`.

```elixir
pid = self()

weather = %{
  name: "weather",
  description: "Current weather for a city",
  input_schema: %{type: "object", properties: %{city: %{type: "string"}}, required: ["city"]},
  eager_input_streaming: true,
  run: fn %{"city" => city} -> {:ok, "sunny in " <> city} end
}

{:ok, response, messages} =
  Jibu.Tools.run(client, "Weather in Berlin?", tools: [weather], on_event: &send(pid, {:claude, &1}))
```

`eager_input_streaming: true` streams large tool inputs as the model writes them.
Jibu sends it unchanged and does not set it for you.
The API does not validate such input. Input that is not valid JSON runs no tool.
The model receives `"the tool input is not valid JSON"` as an error result instead.
The API accepts only an object as input in a replayed turn.
`messages` therefore holds `%{}` as the input of that tool call.

## Server tools

Tools without `:run`, such as web search, go to the API unchanged.
The API runs them. A `pause_turn` response is sent back to let the model continue.
