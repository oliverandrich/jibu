defmodule Jibu.ConvenienceTest do
  use ExUnit.Case, async: true

  import Jibu.TestHelpers

  alias Jibu.Error

  defp reply(text, stop_reason \\ "end_turn") do
    %{"content" => [%{"type" => "text", "text" => text}], "stop_reason" => stop_reason}
  end

  defp defaults_client(opts \\ []) do
    client(__MODULE__, Keyword.merge([model: "claude-opus-5-5", max_tokens: 512], opts))
  end

  defp sent_body do
    assert_received {:request, _conn, raw}
    JSON.decode!(raw)
  end

  describe "client defaults" do
    test "fill in fields the body does not set" do
      capture(__MODULE__, reply("ok"))

      Jibu.messages(defaults_client(defaults: %{temperature: 0}), %{messages: []})

      assert sent_body() == %{
               "model" => "claude-opus-5-5",
               "max_tokens" => 512,
               "temperature" => 0,
               "messages" => []
             }
    end

    test "lose to the body, also when the body uses string keys" do
      capture(__MODULE__, reply("ok"))

      Jibu.messages(defaults_client(), %{"model" => "other", "max_tokens" => 8, "messages" => []})

      assert sent_body() == %{"model" => "other", "max_tokens" => 8, "messages" => []}
    end

    test "count_tokens gets the model but not max_tokens" do
      capture(__MODULE__, %{"input_tokens" => 3})

      Jibu.count_tokens(defaults_client(), %{messages: []})

      assert sent_body() == %{"model" => "claude-opus-5-5", "messages" => []}
    end
  end

  describe "ask/3" do
    test "sends the prompt as a user message and returns the text" do
      capture(__MODULE__, reply("Rhine, Elbe, Danube"))

      assert Jibu.ask(defaults_client(), "Name three rivers.") == {:ok, "Rhine, Elbe, Danube"}

      assert sent_body() == %{
               "model" => "claude-opus-5-5",
               "max_tokens" => 512,
               "messages" => [%{"role" => "user", "content" => "Name three rivers."}]
             }
    end

    test "maps the shortcuts and passes other keywords into the body" do
      capture(__MODULE__, reply("ok"))

      Jibu.ask(defaults_client(), "Hi",
        system: "Be brief.",
        cache: true,
        effort: :low,
        temperature: 0.2,
        some_future_field: %{a: 1}
      )

      body = sent_body()

      assert body["system"] == [
               %{
                 "type" => "text",
                 "text" => "Be brief.",
                 "cache_control" => %{"type" => "ephemeral"}
               }
             ]

      assert body["output_config"] == %{"effort" => "low"}
      assert body["temperature"] == 0.2
      assert body["some_future_field"] == %{"a" => 1}
      refute Map.has_key?(body, "cache")
      refute Map.has_key?(body, "effort")
    end

    test "effort replaces a string-keyed effort in output_config" do
      capture(__MODULE__, reply("ok"))

      Jibu.ask(defaults_client(), "Hi", effort: :low, output_config: %{"effort" => "high"})

      assert_received {:request, _conn, raw}
      refute raw =~ "high"
      assert JSON.decode!(raw)["output_config"] == %{"effort" => "low"}
    end

    test "sends a system prompt without cache as a plain string" do
      capture(__MODULE__, reply("ok"))

      Jibu.ask(defaults_client(), "Hi", system: "Be brief.")

      assert sent_body()["system"] == "Be brief."
    end

    test "appends the prompt to a given history" do
      capture(__MODULE__, reply("ok"))
      history = [%{role: "user", content: "Hi"}, %{role: "assistant", content: "Hello"}]

      Jibu.ask(defaults_client(), "And then?", messages: history)

      assert [_hi, _hello, %{"role" => "user", "content" => "And then?"}] =
               sent_body()["messages"]
    end

    test "accepts a list of content blocks as the prompt" do
      capture(__MODULE__, reply("ok"))
      blocks = [Jibu.Content.image_file("file_1"), %{type: "text", text: "What is this?"}]

      Jibu.ask(defaults_client(), blocks)

      assert [%{"role" => "user", "content" => [%{"type" => "image"}, %{"type" => "text"}]}] =
               sent_body()["messages"]
    end

    test "returns an error when the model refuses or is cut off" do
      Req.Test.stub(__MODULE__, &Req.Test.json(&1, reply("", "refusal")))
      assert {:error, %Error{type: "refusal"}} = Jibu.ask(defaults_client(), "x")

      Req.Test.stub(__MODULE__, &Req.Test.json(&1, reply("Rhine, El", "max_tokens")))
      assert {:error, %Error{type: "max_tokens"}} = Jibu.ask(defaults_client(), "x")
    end

    test "passes API errors through" do
      Req.Test.stub(__MODULE__, &api_error(&1, 400, "invalid_request_error"))
      assert {:error, %Error{status: 400}} = Jibu.ask(defaults_client(), "x")
    end
  end

  describe "extract/4" do
    @schema %{type: "object", properties: %{hours: %{type: "number"}}, required: ["hours"]}

    test "sets the JSON schema format, keeps the effort and decodes the answer" do
      capture(__MODULE__, reply(~s({"hours": 2.5})))

      assert Jibu.extract(defaults_client(), "Workshop 9 to 11:30.", @schema, effort: :low) ==
               {:ok, %{"hours" => 2.5}}

      assert sent_body()["output_config"] == %{
               "effort" => "low",
               "format" => %{
                 "type" => "json_schema",
                 "schema" => JSON.decode!(JSON.encode!(@schema))
               }
             }
    end

    test "returns an error for output cut off at max_tokens" do
      Req.Test.stub(__MODULE__, &Req.Test.json(&1, reply(~s({"hours": ), "max_tokens")))

      assert {:error, %Error{type: "max_tokens"}} =
               Jibu.extract(defaults_client(), "x", @schema)
    end
  end

  test "Tools.run/3 accepts a prompt with shortcuts" do
    capture(__MODULE__, reply("Done"))
    tool = %{name: "noop", input_schema: %{type: "object"}, run: fn _input -> {:ok, "x"} end}

    assert {:ok, response, messages} =
             Jibu.Tools.run(defaults_client(), "Do it.",
               tools: [tool],
               effort: :low,
               max_iterations: 3
             )

    assert Jibu.Response.text(response) == "Done"
    assert [%{role: "user", content: "Do it."}, %{role: "assistant"}] = messages

    body = sent_body()
    assert body["output_config"] == %{"effort" => "low"}
    assert body["tools"] == [%{"name" => "noop", "input_schema" => %{"type" => "object"}}]
    refute Map.has_key?(body, "max_iterations")
  end

  describe "review follow-ups" do
    test "count_tokens gets only the model default" do
      capture(__MODULE__, %{"input_tokens" => 3})

      Jibu.count_tokens(defaults_client(defaults: %{temperature: 0}), %{messages: []})

      assert sent_body() == %{"model" => "claude-opus-5-5", "messages" => []}
    end

    test "ask/3 returns an error when the model stops for a tool" do
      Req.Test.stub(__MODULE__, &Req.Test.json(&1, reply("", "tool_use")))
      assert {:error, %Error{type: "tool_use"}} = Jibu.ask(defaults_client(), "x")

      Req.Test.stub(__MODULE__, &Req.Test.json(&1, reply("partial", "pause_turn")))
      assert {:error, %Error{type: "pause_turn"}} = Jibu.ask(defaults_client(), "x")
    end

    test "a string key in :defaults does not duplicate :model" do
      capture(__MODULE__, reply("ok"))

      Jibu.messages(client(__MODULE__, model: "a", defaults: %{"model" => "b"}), %{messages: []})

      assert {:request, _conn, raw} = assert_received({:request, _conn, _raw})
      assert raw =~ ~s("model":"a")
      refute raw =~ ~s("model":"b")
    end

    test "Tools.run/3 rejects a keyword list instead of sending it as a prompt" do
      assert_raise ArgumentError, ~r/keyword/, fn ->
        Jibu.Tools.run(defaults_client(), model: "x", messages: [])
      end
    end

    test "cache: true marks the last block of a list system prompt" do
      capture(__MODULE__, reply("ok"))
      system = [%{type: "text", text: "a"}, %{type: "text", text: "b"}]

      Jibu.ask(defaults_client(), "Hi", system: system, cache: true)

      assert [%{"text" => "a"} = first, %{"text" => "b", "cache_control" => _cache}] =
               sent_body()["system"]

      refute Map.has_key?(first, "cache_control")
    end

    test "cache: true without a system prompt raises" do
      assert_raise ArgumentError, ~r/system/, fn ->
        Jibu.ask(defaults_client(), "Hi", cache: true)
      end
    end
  end
end
