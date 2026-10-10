defmodule Jibu.Page do
  @moduledoc false

  # Cursor pagination shared by the list endpoints: `data`, `has_more` and `last_id`.
  # A failed page raises, because a stream has no place to return an error tuple.
  # Paging runs forward only; `before_id` would contradict the `after_id` cursor.
  def stream(client, path, query) do
    if Keyword.has_key?(query, :before_id) do
      raise ArgumentError, "stream/2 pages forward only; use list/2 with :before_id"
    end

    Stream.resource(
      fn -> query end,
      fn
        :done ->
          {:halt, :done}

        query ->
          case Jibu.request(client, :get, path, params: query) do
            {:ok, %{"data" => data, "has_more" => true, "last_id" => last_id}} ->
              {data, Keyword.put(query, :after_id, last_id)}

            {:ok, %{"data" => data}} ->
              {data, :done}

            {:error, error} ->
              raise error
          end
      end,
      fn _acc -> :ok end
    )
  end
end
