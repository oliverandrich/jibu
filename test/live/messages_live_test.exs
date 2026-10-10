defmodule Jibu.MessagesLiveTest do
  # Calls the real API and spends money. Run with `mix test --only live`.
  use ExUnit.Case, async: true

  @moduletag :live

  test "a structured output round trip" do
    schema = %{
      type: "object",
      properties: %{answer: %{type: "integer"}},
      required: ["answer"],
      additionalProperties: false
    }

    {:ok, response} =
      Jibu.messages(Jibu.new(), %{
        model: "claude-opus-5-5",
        max_tokens: 1024,
        output_config: %{effort: "low", format: %{type: "json_schema", schema: schema}},
        messages: [%{role: "user", content: "What is 6 times 7?"}]
      })

    assert Jibu.Response.json(response) == {:ok, %{"answer" => 42}}
  end

  test "ask/3 and extract/4 with client defaults" do
    client = Jibu.new(model: "claude-opus-5-5", max_tokens: 1024)

    assert {:ok, text} = Jibu.ask(client, "Reply with the single word: pong", effort: :low)
    assert text =~ ~r/pong/i

    schema = %{
      type: "object",
      properties: %{hours: %{type: "number"}},
      required: ["hours"],
      additionalProperties: false
    }

    assert Jibu.extract(client, "A workshop from 9:00 to 11:30. How many hours?", schema,
             effort: :low
           ) == {:ok, %{"hours" => 2.5}}
  end
end
