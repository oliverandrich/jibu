defmodule Jibu.Content do
  @moduledoc """
  Builds image and document content blocks for the Messages API.

  Extra options are merged into the block unchanged, for example `title:`, `context:`,
  `citations: %{enabled: true}` or `cache_control: %{type: "ephemeral"}`.

      content = [
        Jibu.Content.document("contract.pdf", title: "Contract"),
        %{type: "text", text: "Summarize the termination clauses."}
      ]
  """

  @images %{
    ".jpg" => "image/jpeg",
    ".jpeg" => "image/jpeg",
    ".png" => "image/png",
    ".gif" => "image/gif",
    ".webp" => "image/webp"
  }

  @documents %{".pdf" => "application/pdf", ".txt" => "text/plain", ".md" => "text/plain"}

  @doc "Reads an image file into a base64 image block."
  @spec image(Path.t(), keyword()) :: map()
  def image(path, opts \\ []) do
    media_type = media_type(path, @images)
    image_data(File.read!(path), media_type, opts)
  end

  @doc "Reads a PDF or plain text file into a document block."
  @spec document(Path.t(), keyword()) :: map()
  def document(path, opts \\ []) do
    media_type = media_type(path, @documents)
    document_data(File.read!(path), media_type, opts)
  end

  @doc "Builds a base64 image block from a binary."
  @spec image_data(binary(), String.t(), keyword()) :: map()
  def image_data(data, media_type, opts \\ []) do
    block("image", base64(data, media_type), opts)
  end

  @doc """
  Builds a document block from a binary. `text/plain` becomes a text source, anything else base64.
  """
  @spec document_data(binary(), String.t(), keyword()) :: map()
  def document_data(data, media_type, opts \\ [])

  def document_data(data, "text/plain", opts) do
    block("document", %{type: "text", media_type: "text/plain", data: data}, opts)
  end

  def document_data(data, media_type, opts) do
    block("document", base64(data, media_type), opts)
  end

  @doc "References an image uploaded through `Jibu.Files`."
  @spec image_file(String.t(), keyword()) :: map()
  def image_file(file_id, opts \\ []), do: block("image", %{type: "file", file_id: file_id}, opts)

  @doc "References a document uploaded through `Jibu.Files`."
  @spec document_file(String.t(), keyword()) :: map()
  def document_file(file_id, opts \\ []),
    do: block("document", %{type: "file", file_id: file_id}, opts)

  defp base64(data, media_type),
    do: %{type: "base64", media_type: media_type, data: Base.encode64(data)}

  defp block(type, source, opts), do: Map.merge(%{type: type, source: source}, Map.new(opts))

  defp media_type(path, types) do
    extension = path |> Path.extname() |> String.downcase()

    Map.get_lazy(types, extension, fn ->
      raise ArgumentError,
            "no media type for #{inspect(path)}; supported: #{Enum.join(Map.keys(types), ", ")}. " <>
              "Use the *_data functions with an explicit media type."
    end)
  end
end
