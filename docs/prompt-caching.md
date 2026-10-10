# Prompt caching

Prompt caching reuses the processed prefix of a request.
Cached input tokens cost less and return faster.

## Mark the stable prefix

Put `cache_control` on the last block of the part that stays the same.
Everything before the marker is cached.

```elixir
Jibu.messages(client, %{
  model: "claude-opus-5-5",
  max_tokens: 1024,
  system: [
    %{type: "text", text: instructions},
    %{type: "text", text: project_list, cache_control: %{type: "ephemeral"}}
  ],
  messages: [%{role: "user", content: todays_events}]
})
```

The order of a request is `tools`, then `system`, then `messages`.
A change anywhere in the prefix invalidates the cache from that point on.
Keep timestamps and per-request data after the marker.

## Check that it works

`response.usage` reports the cached part.

```elixir
response.usage["cache_creation_input_tokens"]
response.usage["cache_read_input_tokens"]
```

The first request writes the cache. Later requests with the same prefix read it.
If `cache_read_input_tokens` stays at zero, the prefix changes between requests.
A prefix below the model's minimum length is not cached.

The telemetry event `[:jibu, :request, :stop]` carries the same usage map.
See [Errors, retries and telemetry](errors.md).
