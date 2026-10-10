# Streaming

`Jibu.stream/3` sends a Messages request with `stream: true`.
It calls a function with each event while the answer arrives.

## Stream a response

The function receives every server-sent event as a decoded map with string keys.
This one forwards text deltas to a process, for example a LiveView:

```elixir
pid = self()

{:ok, response} =
  Jibu.stream(client, body, fn
    %{"type" => "content_block_delta", "delta" => %{"type" => "text_delta", "text" => text}} ->
      send(pid, {:text, text})

    _event ->
      :ok
  end)

Jibu.Response.text(response)
```

The result is the assembled message as a `Jibu.Response`, the same as from `Jibu.messages/2`.
Check `stop_reason` before using the answer.

## Events

The function sees all events in order, including `ping` and types Jibu does not know.

| Event | Effect on the assembled message |
| --- | --- |
| `message_start` | Starts the message |
| `content_block_start` | Adds a block at `index` |
| `content_block_delta` | Extends the block, see below |
| `content_block_stop` | Decodes the collected tool input |
| `message_delta` | Sets `stop_reason` and updates `usage` |
| `message_stop`, `ping` | None |

A `text_delta` extends `text`, a `thinking_delta` extends `thinking`.
A `signature_delta` extends `signature`, a `citations_delta` adds to `citations`.
An `input_json_delta` collects the JSON of a tool input. Unknown delta types leave the block unchanged.

Tool input that is not valid JSON at the end of its block stays as the raw JSON string.
This happens when output stops at `max_tokens`.

## Errors

An API error before the stream starts returns `{:error, %Jibu.Error{}}` as with `Jibu.messages/2`.
Such errors are retried by the same rules.

Errors during the stream return `{:error, %Jibu.Error{}}`.
Its `body` holds the message assembled up to that point.

| Cause | `type` | `status` |
| --- | --- | --- |
| An `error` event | The API's error type, for example `"overloaded_error"` | `200` |
| Event data that is not JSON | `"invalid_json"` | `200` |
| A lost connection | `"transport_error"` | `nil` |

The status of an error event is `200` because the HTTP response itself succeeded.
A success response that is not an event stream returns `"invalid_stream"` with the decoded body.

Jibu does not retry once events have arrived, so the function never sees an event twice.
This holds for any `:retry` function. Req's named retry modes, such as `:transient`, do not get this guard.
Exceptions raised in the function reach the caller.
