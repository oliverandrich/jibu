defmodule Jibu.ModelsTest do
  use ExUnit.Case, async: true

  import Jibu.TestHelpers

  alias Jibu.Error
  alias Jibu.Models

  defp model(id), do: %{"type" => "model", "id" => id, "display_name" => id}

  test "get/2 retrieves one model" do
    capture(__MODULE__, model("claude-opus-5-5"))

    assert Models.get(client(__MODULE__), "claude-opus-5-5") == {:ok, model("claude-opus-5-5")}
    assert_received {:request, %{request_path: "/v1/models/claude-opus-5-5"}, _raw}
  end

  test "list/2 returns one page and passes the query through" do
    capture(__MODULE__, %{"data" => [model("a")], "has_more" => true, "last_id" => "a"})

    assert {:ok, %{"data" => [%{"id" => "a"}], "has_more" => true}} =
             Models.list(client(__MODULE__), limit: 1)

    assert_received {:request, %{query_string: "limit=1"}, _raw}
  end

  # The full pagination test for Jibu.Page, which Files and Batches share.
  test "stream/2 follows pages until has_more is false" do
    Req.Test.stub(__MODULE__, fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)

      case conn.query_params["after_id"] do
        nil ->
          Req.Test.json(conn, %{
            "data" => [model("a"), model("b")],
            "has_more" => true,
            "last_id" => "b"
          })

        "b" ->
          Req.Test.json(conn, %{"data" => [model("c")], "has_more" => false, "last_id" => "c"})
      end
    end)

    assert client(__MODULE__) |> Models.stream() |> Enum.map(& &1["id"]) == ["a", "b", "c"]
  end

  test "stream/2 raises a Jibu.Error when a page fails" do
    Req.Test.stub(__MODULE__, &api_error(&1, 401, "authentication_error"))

    assert_raise Error, "authentication_error happened", fn ->
      client(__MODULE__) |> Models.stream() |> Enum.to_list()
    end
  end

  test "stream/2 rejects before_id, because it pages forward only" do
    assert_raise ArgumentError, ~r/before_id/, fn ->
      Models.stream(client(__MODULE__), before_id: "x")
    end
  end
end
