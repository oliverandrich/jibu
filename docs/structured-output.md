# Structured output

Structured output constrains the reply to a JSON schema.
Set it in `output_config.format`.

```elixir
schema = %{
  type: "object",
  properties: %{
    project: %{type: "string"},
    hours: %{type: "number"},
    text: %{type: "string"}
  },
  required: ["project", "hours", "text"],
  additionalProperties: false
}

{:ok, response} =
  Jibu.messages(client, %{
    model: "claude-opus-5-5",
    max_tokens: 1024,
    output_config: %{effort: "low", format: %{type: "json_schema", schema: schema}},
    messages: [%{role: "user", content: "Workshop with MRV, 9 to 11:30."}]
  })
```

## Decode the result

`Jibu.Response.json/1` decodes the text of the reply.

```elixir
case Jibu.Response.json(response) do
  {:ok, %{"project" => project, "hours" => hours}} -> {project, hours}
  {:error, %Jibu.Error{type: "refusal"}} -> :declined
  {:error, %Jibu.Error{type: "max_tokens"}} -> :cut_off
  {:error, %Jibu.Error{type: "invalid_json"}} -> :unreadable
end
```

A refusal is an error. A reply cut off at `max_tokens` or at the context window is an error too.
A partial JSON document is never returned.

## Validate the content

The schema fixes the shape of the reply. It does not check your domain rules.
Validate values against your own data, for example that a project id exists.
