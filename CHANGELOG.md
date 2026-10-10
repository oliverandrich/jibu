# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses [SemVer](https://semver.org/).

## [0.2.0] - 2026-10-10

### Added

- `Jibu.Tools.run/3` runs the tools of one turn concurrently with `max_concurrency:`.
- `Jibu.Tools.run/3` limits the run time of each tool with `tool_timeout:`.
- `Jibu.stream/3` streams a Messages response to a function and returns the assembled message.
- `Jibu.Tools.run/3` streams every turn to a function with `on_event:`.
- `Jibu.ask/3` streams the answer to a function with `on_text:`.
- `Jibu.Error` carries the conversation so far in `messages` when `Jibu.Tools.run/3` fails.

## [0.1.1] - 2026-10-10

### Changed

- The README shows full requests with `Jibu.messages/2` and lists every module with its guide.
- The package links to the changelog on jibu.hexdocs.pm.

## [0.1.0] - 2026-10-10

### Added

- `Jibu.new/1` builds a `Req.Request` with API key, version header, beta header and Req options.
- `Jibu.messages/2` sends a Messages API request body unchanged.
- `Jibu.Response` with `text/1` and `json/1`; `json/1` returns an error for refusals and `max_tokens`.
- `Jibu.Error` carries status, API error type, message, request id and `retry-after`.
- Retries for 408, 409, 429, 5xx and 529, honouring `retry-after` and `x-should-retry`.
- Telemetry span `[:jibu, :request]` with method, path, model, status and usage.
- `Jibu.count_tokens/2` counts the input tokens of a request body.
- `Jibu.Models` lists and retrieves models, with `stream/2` across pages.
- `Jibu.Content` builds image and document blocks from files, binaries or uploaded file ids.
- `Jibu.Files` uploads, lists, retrieves, downloads and deletes files.
- `Jibu.Batches` creates, retrieves, lists, cancels and deletes batches and decodes their results.
- `Jibu.Tools.run/3` runs a tool-use conversation with local `:run` functions until the model stops.
- Guides for getting started, structured output, prompt caching, files, batches, tools, and errors with telemetry.
- Client defaults for `:model`, `:max_tokens` and further body fields.
- `Jibu.ask/3` and `Jibu.extract/4` with the shortcuts `system:`, `cache:`, `effort:` and `messages:`.
- `ask/3`, `extract/4` and `Response.json/1` return an error for turns that wait for tools.
- `Jibu.Tools.run/3` accepts a prompt with the same shortcuts.

[0.2.0]: https://github.com/oliverandrich/jibu/compare/v0.1.1...v0.2.0
[0.1.1]: https://github.com/oliverandrich/jibu/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/oliverandrich/jibu/releases/tag/v0.1.0
