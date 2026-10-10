defmodule Jibu.FilesTest do
  use ExUnit.Case, async: true

  import Jibu.TestHelpers

  alias Jibu.Error
  alias Jibu.Files

  @moduletag :tmp_dir

  @file_meta %{
    "type" => "file",
    "id" => "file_1",
    "filename" => "report.pdf",
    "mime_type" => "application/pdf",
    "size_bytes" => 8
  }

  test "upload/2 sends the file as multipart form data", %{tmp_dir: dir} do
    path = Path.join(dir, "report.pdf")
    File.write!(path, "%PDF-1.7")
    capture(__MODULE__, @file_meta)

    assert Files.upload(client(__MODULE__), path) == {:ok, @file_meta}
    assert_received {:request, conn, raw}
    assert {conn.method, conn.request_path} == {"POST", "/v1/files"}
    assert ["multipart/form-data" <> _rest] = Plug.Conn.get_req_header(conn, "content-type")
    assert raw =~ ~s(name="file"; filename="report.pdf")
    assert raw =~ "content-type: application/pdf"
    assert raw =~ "%PDF-1.7"
  end

  test "upload_data/4 sends a binary under a given filename" do
    capture(__MODULE__, @file_meta)

    assert {:ok, _meta} = Files.upload_data(client(__MODULE__), "hello", "note.txt", "text/plain")
    assert_received {:request, _conn, raw}
    assert raw =~ ~s(filename="note.txt")
    assert raw =~ "content-type: text/plain"
  end

  test "get/2 percent-encodes reserved characters in the id" do
    capture(__MODULE__, @file_meta)

    assert {:ok, _meta} = Files.get(client(__MODULE__), "a/b?c")
    assert_received {:request, %{request_path: "/v1/files/a%2Fb%3Fc", query_string: ""}, _raw}
  end

  test "get/2, download/2 and delete/2 address one file" do
    Req.Test.stub(__MODULE__, fn conn ->
      case {conn.method, conn.request_path} do
        {"GET", "/v1/files/file_1"} ->
          Req.Test.json(conn, @file_meta)

        {"GET", "/v1/files/file_1/content"} ->
          conn
          |> Plug.Conn.put_resp_content_type("application/octet-stream")
          |> Plug.Conn.send_resp(200, "%PDF-1.7")

        {"DELETE", "/v1/files/file_1"} ->
          Req.Test.json(conn, %{"id" => "file_1", "type" => "file_deleted"})
      end
    end)

    client = client(__MODULE__)
    assert Files.get(client, "file_1") == {:ok, @file_meta}
    assert Files.download(client, "file_1") == {:ok, "%PDF-1.7"}
    assert Files.delete(client, "file_1") == {:ok, %{"id" => "file_1", "type" => "file_deleted"}}
  end

  test "list/2 and stream/2 read /v1/files" do
    capture(__MODULE__, %{"data" => [@file_meta], "has_more" => false})

    assert {:ok, %{"data" => [@file_meta]}} = Files.list(client(__MODULE__))
    assert client(__MODULE__) |> Files.stream() |> Enum.to_list() == [@file_meta]
    assert_received {:request, %{request_path: "/v1/files"}, _raw}
  end

  test "download/2 reports the API error of a failed download" do
    Req.Test.stub(__MODULE__, &api_error(&1, 403, "permission_error"))

    assert {:error, %Error{status: 403, type: "permission_error"}} =
             Files.download(client(__MODULE__), "file_1")
  end
end
