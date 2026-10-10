defmodule Jibu.ResponseTest do
  use ExUnit.Case, async: true

  alias Jibu.Error
  alias Jibu.Response

  defp response(content, stop_reason \\ "end_turn") do
    Response.new(%{"content" => content, "stop_reason" => stop_reason})
  end

  describe "text/1" do
    test "joins all text blocks and skips other blocks" do
      content = [
        %{"type" => "thinking", "thinking" => ""},
        %{"type" => "text", "text" => "Hello, "},
        %{"type" => "tool_use", "id" => "t1", "name" => "x", "input" => %{}},
        %{"type" => "text", "text" => "world"}
      ]

      assert Response.text(response(content)) == "Hello, world"
    end
  end

  describe "json/1" do
    test "decodes the text of a structured output" do
      text = ~s({"project": "P00-000000", "hours": 0.5})

      assert Response.json(response([%{"type" => "text", "text" => text}])) ==
               {:ok, %{"project" => "P00-000000", "hours" => 0.5}}
    end

    for {stop_reason, type} <- [
          {"refusal", "refusal"},
          {"max_tokens", "max_tokens"},
          {"model_context_window_exceeded", "context_window_exceeded"}
        ] do
      test "returns a #{type} error for stop_reason #{stop_reason}" do
        response = response([%{"type" => "text", "text" => ~s({"a": )}], unquote(stop_reason))
        assert {:error, %Error{type: unquote(type)}} = Response.json(response)
      end
    end

    test "returns an error for text that is not JSON" do
      assert {:error, %Error{type: "invalid_json"}} =
               Response.json(response([%{"type" => "text", "text" => "not json"}]))
    end
  end
end
