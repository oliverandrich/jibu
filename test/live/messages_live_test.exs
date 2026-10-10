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

  test "stream/3 passes text deltas and returns the assembled message" do
    pid = self()

    {:ok, response} =
      Jibu.stream(
        Jibu.new(),
        %{
          model: "claude-opus-5-5",
          max_tokens: 1024,
          output_config: %{effort: "low"},
          messages: [%{role: "user", content: "Count from 1 to 5, separated by spaces."}]
        },
        fn
          %{"type" => "content_block_delta", "delta" => %{"type" => "text_delta", "text" => text}} ->
            send(pid, {:text, text})

          _event ->
            :ok
        end
      )

    assert response.stop_reason == "end_turn"
    assert Jibu.Response.text(response) =~ "1 2 3 4 5"
    assert_received {:text, _first}
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
