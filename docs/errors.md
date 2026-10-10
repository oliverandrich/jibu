# Errors, retries and telemetry

## Errors

Every function returns `{:ok, result}` or `{:error, %Jibu.Error{}}`.
The `stream/2` functions raise `Jibu.Error`, because a stream cannot return an error tuple.
They page forward only and reject `:before_id`.

| Field | Meaning |
| --- | --- |
| `type` | The API's `error.type`, or one of Jibu's own types |
| `message` | Human-readable description |
| `status` | HTTP status, `nil` without a response |
| `request_id` | The API's request id, for support requests |
| `retry_after` | Delay suggested by the API, in milliseconds |
| `reason` | The underlying exception of a transport error |
| `body` | The decoded response body |

Jibu's own types:

| Type | Cause |
| --- | --- |
| `"transport_error"` | No HTTP response, for example a refused connection |
| `"refusal"` | `Jibu.Response.json/1` on a refused request |
| `"max_tokens"` | `Jibu.Response.json/1` on output cut off at `max_tokens` |
| `"context_window_exceeded"` | `Jibu.Response.json/1` on output cut off at the context window |
| `"tool_use"`, `"pause_turn"` | `ask/3`, `extract/4` or `Jibu.Response.json/1` on a turn that waits for tools |
| `"invalid_json"` | `Jibu.Response.json/1` on text that is not JSON, or stream event data that is not JSON |
| `"invalid_stream"` | `Jibu.stream/3` got a success response that is not an event stream |
| `"max_iterations"` | `Jibu.Tools.run/3` reached its request cap |

An error status without a JSON error body gets the type `"http_error"`.

## Retries

Jibu retries these responses, for every HTTP method:

- 408, 409 and 429
- every 5xx status, including 529, the API's `overloaded_error`

It also retries timeouts, refused connections and closed connections.

A `retry-after` header sets the delay. Without one, Req backs off exponentially with jitter.
An `x-should-retry` header from the API overrides the status rule.
Req makes at most 3 retries by default. Set `:max_retries` to change that.

```elixir
Jibu.new(max_retries: 5)
Jibu.new(retry: false)
```

## Telemetry

Every request runs in a `:telemetry.span/3` named `[:jibu, :request]`.

| Event | Measurements | Metadata |
| --- | --- | --- |
| `[:jibu, :request, :start]` | `system_time`, `monotonic_time` | `method`, `path`, `model` |
| `[:jibu, :request, :stop]` | `duration`, `monotonic_time` | `method`, `path`, `model`, `status`, `usage` |
| `[:jibu, :request, :exception]` | `duration`, `monotonic_time` | `method`, `path`, `model`, `kind`, `reason`, `stacktrace` |

`model` is `nil` for endpoints without a model in the body.
`status` is `nil` for transport errors. `usage` is the API's usage map, or `nil`.
Retries happen inside one span, so `duration` includes them.

```elixir
require Logger

:telemetry.attach("jibu-usage", [:jibu, :request, :stop], fn _event, %{duration: d}, meta, _ ->
  ms = System.convert_time_unit(d, :native, :millisecond)
  Logger.info("#{meta.model} #{meta.status} #{ms}ms #{inspect(meta.usage)}")
end, nil)
```
