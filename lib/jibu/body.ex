defmodule Jibu.Body do
  @moduledoc false

  # Request bodies may use atom or string keys. A string key wins when both exist.

  # Returns the key actually present, so a caller writes back under the same key.
  def fetch(map, key, default) do
    string = Atom.to_string(key)

    if Map.has_key?(map, string),
      do: {string, map[string]},
      else: {key, Map.get(map, key, default)}
  end

  # Adds each default the body does not set, under either key form.
  def put_defaults(body, defaults) do
    present = MapSet.new(Map.keys(body), &to_string/1)

    Enum.reduce(defaults, body, fn {key, value}, body ->
      if MapSet.member?(present, to_string(key)), do: body, else: Map.put(body, key, value)
    end)
  end

  def get(map, key) when is_map(map), do: map |> fetch(key, nil) |> elem(1)
  def get(_other, _key), do: nil
end
