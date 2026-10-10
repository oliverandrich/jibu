defmodule Jibu.Batches do
  @moduledoc """
  The Message Batches API: many Messages requests processed asynchronously at half price.

      {:ok, batch} =
        Jibu.Batches.create(client, %{
          requests: [%{custom_id: "a", params: %{model: "claude-opus-5-5", max_tokens: 1024, messages: messages}}]
        })

  Poll `get/2` until `processing_status` is `"ended"`. Then read `results/2`.
  Results arrive in any order. Match them by `custom_id`.
  Results are the API's JSON with string keys. See the [batches guide](batches.md).
  """

  alias Jibu.Error

  @path "/v1/messages/batches"

  @doc "Creates a batch. The body is sent unchanged."
  @spec create(Req.Request.t(), map()) :: {:ok, map()} | {:error, Error.t()}
  def create(client, body) when is_map(body), do: Jibu.request(client, :post, @path, json: body)

  @doc "Retrieves a batch, including its `processing_status` and `request_counts`."
  @spec get(Req.Request.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get(client, id), do: Jibu.request(client, :get, @path <> "/:id", path_params: [id: id])

  @doc "Cancels a batch. Requests already processed keep their results."
  @spec cancel(Req.Request.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def cancel(client, id),
    do: Jibu.request(client, :post, @path <> "/:id/cancel", path_params: [id: id])

  @doc "Deletes a batch that has ended."
  @spec delete(Req.Request.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def delete(client, id),
    do: Jibu.request(client, :delete, @path <> "/:id", path_params: [id: id])

  @doc "Returns one page. `query` takes the API's parameters, such as `:limit` and `:after_id`."
  @spec list(Req.Request.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def list(client, query \\ []), do: Jibu.request(client, :get, @path, params: query)

  @doc "Streams all batches across pages, forward only. Raises `Jibu.Error` when a page fails."
  @spec stream(Req.Request.t(), keyword()) :: Enumerable.t()
  def stream(client, query \\ []), do: Jibu.Page.stream(client, @path, query)

  @doc """
  Fetches the results of an ended batch and returns them as a lazily decoded stream of maps.

  The whole JSONL body is held in memory while the stream is consumed.
  """
  @spec results(Req.Request.t(), String.t()) :: {:ok, Enumerable.t()} | {:error, Error.t()}
  def results(client, id) do
    with {:ok, body} <-
           Jibu.request(client, :get, @path <> "/:id/results",
             path_params: [id: id],
             decode_body: false
           ) do
      {:ok,
       body
       |> String.splitter("\n", trim: true)
       |> Stream.map(&JSON.decode!/1)}
    end
  end
end
