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

## Server tools

Tools without `:run`, such as web search, go to the API unchanged.
The API runs them. A `pause_turn` response is sent back to let the model continue.
