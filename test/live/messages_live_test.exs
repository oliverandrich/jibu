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
end
