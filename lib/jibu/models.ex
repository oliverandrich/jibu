defmodule Jibu.Models do
  @moduledoc """
  The Models API: the models available to the API key, with their capabilities.
  Results are the API's JSON with string keys.
  """

  alias Jibu.Error

  @path "/v1/models"

  @doc "Retrieves one model by id or alias."
  @spec get(Req.Request.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get(client, id),
    do: Jibu.request(client, :get, @path <> "/:id", path_params: [id: id])

  @doc """
  Returns one page. `query` takes the API's parameters, such as `:limit`, `:after_id` and `:before_id`.
  """
  @spec list(Req.Request.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def list(client, query \\ []), do: Jibu.request(client, :get, @path, params: query)

  @doc """
  Streams all models across pages, forward only. Raises `Jibu.Error` when a page fails.
  """
  @spec stream(Req.Request.t(), keyword()) :: Enumerable.t()
  def stream(client, query \\ []), do: Jibu.Page.stream(client, @path, query)
end
