defmodule Jibu.Files do
  @moduledoc """
  The Files API: upload a file once and reference it by id.
  `Jibu.Content` builds the reference blocks.
  Results are the API's JSON with string keys. See the [files guide](files.md).
  """

  alias Jibu.Error

  @path "/v1/files"

  @doc """
  Uploads a file from disk. The content type comes from the file extension.

  A missing or unreadable file raises `File.Error`, like `Jibu.Content.image/2`.
  """
  @spec upload(Req.Request.t(), Path.t()) :: {:ok, map()} | {:error, Error.t()}
  def upload(client, path) do
    upload_data(client, File.stream!(path, 65_536), Path.basename(path), MIME.from_path(path))
  end

  @doc "Uploads a binary under the given filename and content type."
  @spec upload_data(Req.Request.t(), iodata() | Enumerable.t(), String.t(), String.t()) ::
          {:ok, map()} | {:error, Error.t()}
  def upload_data(client, data, filename, content_type) do
    part = {data, filename: filename, content_type: content_type}
    Jibu.request(client, :post, @path, form_multipart: [file: part])
  end

  @doc "Retrieves a file's metadata."
  @spec get(Req.Request.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get(client, id), do: Jibu.request(client, :get, @path <> "/:id", path_params: [id: id])

  @doc """
  Downloads a file's content as a binary. The API allows this only for files it created.
  """
  @spec download(Req.Request.t(), String.t()) :: {:ok, binary()} | {:error, Error.t()}
  def download(client, id),
    do:
      Jibu.request(client, :get, @path <> "/:id/content",
        path_params: [id: id],
        decode_body: false
      )

  @doc "Deletes a file."
  @spec delete(Req.Request.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def delete(client, id),
    do: Jibu.request(client, :delete, @path <> "/:id", path_params: [id: id])

  @doc "Returns one page. `query` takes the API's parameters, such as `:limit` and `:after_id`."
  @spec list(Req.Request.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def list(client, query \\ []), do: Jibu.request(client, :get, @path, params: query)

  @doc "Streams all files across pages, forward only. Raises `Jibu.Error` when a page fails."
  @spec stream(Req.Request.t(), keyword()) :: Enumerable.t()
  def stream(client, query \\ []), do: Jibu.Page.stream(client, @path, query)
end
