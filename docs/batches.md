# Batches

The Message Batches API processes many requests asynchronously at half the price.
Use it when nobody waits for the answer.

## Create a batch

Each request has a `custom_id` and the `params` of a normal Messages request.

```elixir
requests =
  for {id, events} <- days do
    %{
      custom_id: id,
      params: %{model: "claude-opus-5-5", max_tokens: 1024, messages: [%{role: "user", content: events}]}
    }
  end

{:ok, %{"id" => batch_id}} = Jibu.Batches.create(client, %{requests: requests})
```

## Wait for the result

Poll `Jibu.Batches.get/2` until `processing_status` is `"ended"`.

```elixir
{:ok, batch} = Jibu.Batches.get(client, batch_id)
batch["processing_status"]
batch["request_counts"]
```

## Read the results

```elixir
{:ok, results} = Jibu.Batches.results(client, batch_id)

for %{"custom_id" => id, "result" => result} <- results do
  case result do
    %{"type" => "succeeded", "message" => message} -> {id, Jibu.Response.new(message)}
    %{"type" => other} -> {id, other}
  end
end
```

Results arrive in any order. Match them by `custom_id`, never by position.
A result type is `"succeeded"`, `"errored"`, `"canceled"` or `"expired"`.
`results/2` holds the whole result file in memory while you consume it.

## Cancel and delete

```elixir
Jibu.Batches.cancel(client, batch_id)
Jibu.Batches.delete(client, batch_id)
```

Cancelling keeps the results of requests already processed.
