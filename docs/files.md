# Images, documents and files

## Inline content

`Jibu.Content` builds content blocks from files or binaries.
The data is sent base64-encoded with each request.

```elixir
Jibu.messages(client, %{
  model: "claude-opus-5-5",
  max_tokens: 1024,
  messages: [
    %{
      role: "user",
      content: [
        Jibu.Content.document("contract.pdf", title: "Contract"),
        Jibu.Content.image("scan.png"),
        %{type: "text", text: "Compare the scan with the contract."}
      ]
    }
  ]
})
```

The media type comes from the file extension.
Images support `.jpg`, `.jpeg`, `.png`, `.gif` and `.webp`.
Documents support `.pdf`, `.txt` and `.md`.
Text files become a `text` source, PDFs a `base64` source.

For binaries, pass the media type yourself:

```elixir
Jibu.Content.image_data(png_binary, "image/png")
Jibu.Content.document_data(pdf_binary, "application/pdf")
```

Extra options are merged into the block unchanged:

```elixir
Jibu.Content.document("contract.pdf", citations: %{enabled: true}, cache_control: %{type: "ephemeral"})
```

## Upload once with the Files API

Upload a file once and reference it by id in later requests.

```elixir
{:ok, %{"id" => file_id}} = Jibu.Files.upload(client, "handbook.pdf")

Jibu.Content.document_file(file_id)
Jibu.Content.image_file(image_id)
```

`Jibu.Files.upload/2` streams the file from disk.
`Jibu.Files.upload_data/4` uploads a binary with a filename and content type.

## Manage files

```elixir
{:ok, meta} = Jibu.Files.get(client, file_id)
{:ok, _deleted} = Jibu.Files.delete(client, file_id)
client |> Jibu.Files.stream() |> Enum.to_list()
```

`Jibu.Files.download/2` returns the content as a binary.
The API allows downloads only for files it created, not for your uploads.
