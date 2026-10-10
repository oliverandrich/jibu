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

## Usage

```elixir
client = Jibu.new(model: "claude-opus-5-5", max_tokens: 1024)

{:ok, text} = Jibu.ask(client, "Name three rivers in Germany.", effort: :low)

{:ok, booking} = Jibu.extract(client, "Workshop with MRV, 9 to 11:30.", schema)
```

`Jibu.messages/2` takes a full request body and sends it unchanged.
In tests, pass `plug: {Req.Test, MyStub}` to `Jibu.new/1`.

## Installation

Add Jibu to the dependencies in `mix.exs`:

```elixir
{:jibu, "~> 0.1"}
```

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
