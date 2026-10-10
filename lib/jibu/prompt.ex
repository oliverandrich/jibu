defmodule Jibu.Prompt do
  @moduledoc false

  # Builds a Messages body from a prompt and keyword shortcuts.
  # `system:`, `cache:`, `effort:` and `messages:` have a fixed meaning.
  # Every other keyword becomes a body field unchanged.
  def body(prompt, opts) do
    {system, opts} = Keyword.pop(opts, :system)
    {cache?, opts} = Keyword.pop(opts, :cache, false)
    {effort, opts} = Keyword.pop(opts, :effort)
    {history, opts} = Keyword.pop(opts, :messages, [])

    opts
    |> Map.new()
    |> Map.put(:messages, history ++ [%{role: "user", content: prompt}])
    |> put_system(system, cache?)
    |> put_effort(effort)
  end

  # Writes under the key form the caller used, so a string key is not sent twice.
  def put_output_config(body, key, value) do
    Map.update(body, :output_config, %{key => value}, fn config ->
      {key, _value} = Jibu.Body.fetch(config, key, nil)
      Map.put(config, key, value)
    end)
  end

  defp put_system(_body, nil, true),
    do: raise(ArgumentError, "cache: true needs a system: prompt")

  defp put_system(body, nil, _cache?), do: body

  defp put_system(body, system, true) when is_binary(system),
    do: put_system(body, [%{type: "text", text: system}], true)

  defp put_system(body, [_first | _rest] = system, true) do
    cached = List.update_at(system, -1, &Map.put(&1, :cache_control, %{type: "ephemeral"}))
    Map.put(body, :system, cached)
  end

  defp put_system(body, system, _cache?), do: Map.put(body, :system, system)

  defp put_effort(body, nil), do: body
  defp put_effort(body, effort), do: put_output_config(body, :effort, to_string(effort))
end
