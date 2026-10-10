defmodule Jibu.Response do
  @moduledoc """
  A Messages API response.

  The fields mirror the API's JSON with string keys.
  `body` holds the complete decoded body, including fields Jibu does not lift.
  """

  alias Jibu.Error

  @type t :: %__MODULE__{
          id: String.t() | nil,
          model: String.t() | nil,
          content: [map()],
          stop_reason: String.t() | nil,
          usage: map() | nil,
          body: map()
        }

  defstruct [:id, :model, :stop_reason, :usage, content: [], body: %{}]

  # Stop reasons that leave no complete answer, with the error each one returns.
  @stop_errors %{
    "refusal" => {"refusal", "the model refused the request"},
    "max_tokens" => {"max_tokens", "the output reached max_tokens"},
    "tool_use" => {"tool_use", "the model asked for a tool; use Jibu.Tools.run/3"},
    "pause_turn" => {"pause_turn", "the model paused a long turn; use Jibu.Tools.run/3"},
    "model_context_window_exceeded" =>
      {"context_window_exceeded", "the output reached the context window"}
  }

  @doc false
  def new(body) when is_map(body) do
    %__MODULE__{
      id: body["id"],
      model: body["model"],
      content: body["content"] || [],
      stop_reason: body["stop_reason"],
      usage: body["usage"],
      body: body
    }
  end

  @doc """
  Returns the text of all `text` blocks, joined without a separator.
  """
  @spec text(t()) :: String.t()
  def text(%__MODULE__{content: content}) do
    for %{"type" => "text", "text" => text} <- content, into: "", do: text
  end

  @doc """
  Decodes the text of a structured output as JSON.

  A refusal returns an error instead of a result.
  Output cut off at `max_tokens` or at the context window returns an error, never partial JSON.
  See the [structured output guide](structured-output.md).
  """
  @spec json(t()) :: {:ok, term()} | {:error, Error.t()}
  def json(%__MODULE__{} = response) do
    case stop_error(response) do
      nil -> decode(response)
      error -> {:error, error}
    end
  end

  # The error for a stop reason that leaves no usable answer, or nil.
  @doc false
  def stop_error(%__MODULE__{stop_reason: reason} = response) do
    case @stop_errors do
      %{^reason => {type, message}} -> %Error{type: type, message: message, body: response.body}
      _other -> nil
    end
  end

  defp decode(response) do
    case JSON.decode(text(response)) do
      {:ok, decoded} ->
        {:ok, decoded}

      {:error, reason} ->
        {:error,
         %Error{
           type: "invalid_json",
           message: "the text is not valid JSON: #{inspect(reason)}",
           body: response.body
         }}
    end
  end
end
