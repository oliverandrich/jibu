defmodule Jibu.ContentTest do
  use ExUnit.Case, async: true

  alias Jibu.Content

  @moduletag :tmp_dir

  test "image/2 reads a file into a base64 image block", %{tmp_dir: dir} do
    path = Path.join(dir, "photo.PNG")
    File.write!(path, <<137, 80, 78, 71>>)

    assert Content.image(path) == %{
             type: "image",
             source: %{
               type: "base64",
               media_type: "image/png",
               data: Base.encode64(<<137, 80, 78, 71>>)
             }
           }
  end

  test "document/2 reads a PDF into a base64 document block and merges extra fields", %{
    tmp_dir: dir
  } do
    path = Path.join(dir, "contract.pdf")
    File.write!(path, "%PDF-1.7")

    assert Content.document(path, title: "Contract", citations: %{enabled: true}) == %{
             type: "document",
             source: %{
               type: "base64",
               media_type: "application/pdf",
               data: Base.encode64("%PDF-1.7")
             },
             title: "Contract",
             citations: %{enabled: true}
           }
  end

  test "document/2 sends plain text files as text sources", %{tmp_dir: dir} do
    path = Path.join(dir, "notes.md")
    File.write!(path, "# Notes")

    assert Content.document(path).source == %{
             type: "text",
             media_type: "text/plain",
             data: "# Notes"
           }
  end

  test "an unknown extension raises with the supported list", %{tmp_dir: dir} do
    path = Path.join(dir, "data.bin")
    File.write!(path, "x")

    assert_raise ArgumentError, ~r/media type/, fn -> Content.image(path) end
  end

  test "image_data/3 and document_data/3 take a binary with an explicit media type" do
    assert Content.image_data("abc", "image/webp").source.media_type == "image/webp"
    assert Content.document_data("%PDF", "application/pdf").source.data == Base.encode64("%PDF")
  end

  test "file references point at an uploaded file id" do
    assert Content.image_file("file_1") == %{
             type: "image",
             source: %{type: "file", file_id: "file_1"}
           }

    assert Content.document_file("file_2", title: "Report") == %{
             type: "document",
             source: %{type: "file", file_id: "file_2"},
             title: "Report"
           }
  end
end
