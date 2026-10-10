# Getting started

## Install

Add Jibu to your dependencies in `mix.exs`:

```elixir
{:jibu, github: "oliverandrich/jibu"}
```

## Create a client

`Jibu.new/1` returns a `Req.Request`. Build it once and reuse it.

```elixir
client = Jibu.new(api_key: System.fetch_env!("ANTHROPIC_API_KEY"))
```

Without `:api_key`, Jibu reads the `ANTHROPIC_API_KEY` environment variable.
Beta features need their names in `:betas`:

```elixir
client = Jibu.new(betas: ["some-beta-2026-01-01"])
```

Every other option goes to `Req.new/1`, for example `:receive_timeout`.

## Send a message

The body is a plain map. Jibu sends it unchanged.

```elixir
{:ok, response} =
  Jibu.messages(client, %{
    model: "claude-opus-5-5",
    max_tokens: 1024,
    messages: [%{role: "user", content: "Name three rivers in Germany."}]
  })

Jibu.Response.text(response)
```

`Jibu.Response` lifts `id`, `model`, `content`, `stop_reason` and `usage` from the reply.
`response.body` holds the complete decoded JSON with string keys.

## Check the stop reason

`stop_reason` tells you why the model stopped.

- `"end_turn"`: the answer is complete.
- `"max_tokens"`: the answer was cut off. Raise `max_tokens` or shorten the task.
- `"refusal"`: the model declined. The content is not an answer.
- `"tool_use"`: the model asks for a tool. See [Tools](tools.md).

## Set the effort

`output_config.effort` trades depth of reasoning against tokens and latency.

```elixir
Jibu.messages(client, %{
  model: "claude-opus-5-5",
  max_tokens: 1024,
  output_config: %{effort: "low"},
  messages: messages
})
```

Use `"low"` for classification and short extraction. Measure before raising it.

## Count tokens

`Jibu.count_tokens/2` takes the same body as `Jibu.messages/2`. The API does not bill it.

```elixir
{:ok, %{"input_tokens" => count}} = Jibu.count_tokens(client, body)
```

## List models

```elixir
{:ok, model} = Jibu.Models.get(client, "claude-opus-5-5")
client |> Jibu.Models.stream() |> Enum.map(& &1["id"])
```

## Test without the network

Pass a `Req.Test` plug as a client option. No request leaves the test process.

```elixir
client = Jibu.new(api_key: "test", plug: {Req.Test, MyApp.Claude}, retry: false)

Req.Test.stub(MyApp.Claude, fn conn ->
  Req.Test.json(conn, %{
    "content" => [%{"type" => "text", "text" => "Hello"}],
    "stop_reason" => "end_turn"
  })
end)
```

`Req.Test` needs the `plug` package in your test dependencies.
