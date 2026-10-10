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

  def get(map, key) when is_map(map), do: map |> fetch(key, nil) |> elem(1)
  def get(_other, _key), do: nil
end
