# Jibu

A thin client for the Anthropic API, built on [Req](https://hex.pm/packages/req).

Jibu sends request bodies unchanged.
It has no model list and no parameter schema.
New API fields therefore work without a new release.

## Features

- `ask/3` and `extract/4` for text and structured output, with client defaults
- Full Messages requests with effort and prompt caching
- Token counting and the Models API
- Image and document content, and the Files API
- Message Batches
- A tool-use loop with local tool functions
- Typed errors, retries with `retry-after`, and telemetry
- Tests through `Req.Test`, without the network

Jibu is not affiliated with or endorsed by Anthropic.

## Installation

Add Jibu to the dependencies in `mix.exs`:

```elixir
{:jibu, "~> 0.1"}
```

## Quick start

```elixir
client = Jibu.new(model: "claude-opus-5-5", max_tokens: 1024)

{:ok, text} = Jibu.ask(client, "Name three rivers in Germany.", effort: :low)

{:ok, booking} = Jibu.extract(client, "Workshop with MRV, 9 to 11:30.", schema)
```

Without `:api_key`, Jibu reads `ANTHROPIC_API_KEY` from the environment.

## Full requests

`Jibu.messages/2` takes the whole request body as a map and returns the whole response.
Jibu sends the body unchanged, so every field of the API works, including new ones.

```elixir
{:ok, response} =
  Jibu.messages(client, %{
    system: [%{type: "text", text: "You sort bookings.", cache_control: %{type: "ephemeral"}}],
    messages: [%{role: "user", content: "Workshop with MRV, 9 to 11:30."}],
    output_config: %{effort: "low"}
  })

Jibu.Response.text(response)
response.stop_reason
response.usage
```

The client defaults fill in `model` and `max_tokens`. A field in the body wins over its default.

## More of the API

| Module | Covers | Guide |
| --- | --- | --- |
| `Jibu` | `count_tokens/2` | [Getting started](docs/getting-started.md) |
| `Jibu.Models` | Listing and retrieving models | [Getting started](docs/getting-started.md) |
| `Jibu.Content` | Image and document blocks from files, binaries or file ids | [Files](docs/files.md) |
| `Jibu.Files` | Upload, list, download and delete files | [Files](docs/files.md) |
| `Jibu.Batches` | Message Batches at half price | [Batches](docs/batches.md) |
| `Jibu.Tools` | A tool-use loop with local functions | [Tools](docs/tools.md) |
| `Jibu.Error` | Error types, retries and telemetry | [Errors](docs/errors.md) |

In tests, pass `plug: {Req.Test, MyStub}` to `Jibu.new/1`. No request then leaves the test.

## Documentation

- [Getting started](docs/getting-started.md)
- [Structured output](docs/structured-output.md)
- [Prompt caching](docs/prompt-caching.md)
- [Images, documents and files](docs/files.md)
- [Batches](docs/batches.md)
- [Tools](docs/tools.md)
- [Errors, retries and telemetry](docs/errors.md)
- [Contributing](https://github.com/oliverandrich/jibu/blob/main/CONTRIBUTING.md): development setup, mise commands and checks.
- [Changelog](CHANGELOG.md)
