# Getting started

## Install

Add Jibu to your dependencies in `mix.exs`:

```elixir
{:jibu, "~> 0.1"}
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

Set the model and `max_tokens` once on the client:

```elixir
client = Jibu.new(model: "claude-opus-5-5", max_tokens: 1024)
```

`Jibu.messages/2` and `Jibu.count_tokens/2` apply these defaults. A field set in the body wins.
Batch requests do not get them.
`:defaults` takes further fields, for example `defaults: %{temperature: 0}`.
Every other option goes to `Req.merge/2`, for example `:receive_timeout`.

## Ask a question

`Jibu.ask/3` sends a prompt and returns the text of the answer.

```elixir
{:ok, text} = Jibu.ask(client, "Name three rivers in Germany.")
```

The prompt is a string or a list of content blocks, see [Images, documents and files](files.md).
These shortcuts have a fixed meaning:

- `system:` sets the system prompt. `cache: true` marks it for [prompt caching](prompt-caching.md).
- `effort:` sets `output_config.effort`.
- `messages:` passes an earlier conversation. The prompt is appended to it.

Every other keyword becomes a body field unchanged.

```elixir
{:ok, text} =
  Jibu.ask(client, "And the longest of them?",
    system: "Answer in one sentence.",
    effort: :low,
    temperature: 0,
    messages: [
      %{role: "user", content: "Name three rivers in Germany."},
      %{role: "assistant", content: "Rhine, Elbe and Danube."}
    ]
  )
```

A refusal and output cut off at `max_tokens` return `{:error, %Jibu.Error{}}`.
So does a turn that waits for a tool. Use [Tools](tools.md) for those.

## Send a full request

`Jibu.messages/2` takes the whole body as a plain map and returns the whole response.
Jibu sends the body unchanged, apart from the client defaults.

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
With `ask/3` and `extract/4`, the `effort:` shortcut sets it.

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
Of the client defaults, only the model applies here.

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
