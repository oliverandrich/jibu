defmodule Jibu.Credo.NoBeanIdsTest do
  use ExUnit.Case, async: true

  alias Jibu.Credo.NoBeanIds

  # The prefix is assembled so this file does not report itself.
  @prefix "jibu" <> "-"

  # Credo parses sources through its own application, which `runtime: false` does not start.
  setup_all do
    case Application.ensure_all_started(:credo) do
      {:ok, _started} -> :ok
      {:error, {:credo, {{:already_started, _pid}, _}}} -> :ok
    end
  end

  defp issues(source) do
    source
    |> Credo.SourceFile.parse("lib/jibu/example.ex")
    |> NoBeanIds.run([])
  end

  test "a bean id in a comment is reported" do
    assert [issue] = issues("# Follows #{@prefix}ab12.\n")
    assert issue.trigger == @prefix <> "ab12"
    assert issue.line_no == 1
  end

  test "a bean id ending a sentence is reported" do
    assert [_issue] = issues("# See #{@prefix}x9z0.\n")
  end

  test "a longer name with the same prefix is not reported" do
    assert issues("# The #{@prefix}docker-image tag.\n") == []
  end

  test "a file name with the same prefix is not reported" do
    assert issues("# Writes #{@prefix}logo.svg to disk.\n") == []
  end

  test "a string literal ending after four characters is not reported" do
    assert issues(~s|name = "#{@prefix}demo"\n|) == []
  end
end
