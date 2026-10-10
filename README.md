# Jibu

A thin client for the Anthropic API, built on [Req](https://hex.pm/packages/req).

Jibu sends request bodies unchanged.
It has no model list and no parameter schema.
New API fields therefore work without a new release.

## Features

- Messages with structured output, effort and prompt caching
- Token counting and the Models API
- Image and document content, and the Files API
- Message Batches
- A tool-use loop with local tool functions
- Typed errors, retries with `retry-after`, and telemetry
- Tests through `Req.Test`, without the network

Jibu is not affiliated with or endorsed by Anthropic.

## Usage

```elixir
client = Jibu.new(api_key: System.fetch_env!("ANTHROPIC_API_KEY"))

{:ok, response} =
  Jibu.messages(client, %{
    model: "claude-opus-5-5",
    max_tokens: 1024,
    output_config: %{effort: "low", format: %{type: "json_schema", schema: schema}},
    messages: [%{role: "user", content: "..."}]
  })

{:ok, data} = Jibu.Response.json(response)
```

Every option besides `:api_key`, `:betas` and `:base_url` goes to `Req.new/1`.
In tests, pass `plug: {Req.Test, MyStub}`.

## Status

Work in progress towards 0.1. Not yet published on Hex.

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
