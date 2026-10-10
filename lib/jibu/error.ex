defmodule Jibu.Error do
  @moduledoc """
  An error from the Anthropic API, the transport, or a response that cannot be used.

  `type` is the API's `error.type` for API errors, for example `"rate_limit_error"`.
  Jibu's own types are `"transport_error"`, `"http_error"`, `"refusal"`, `"max_tokens"`,
  `"context_window_exceeded"`, `"tool_use"`, `"pause_turn"`, `"invalid_json"` and
  `"max_iterations"`.
  `status` and `request_id` are `nil` when no HTTP response exists.
  `retry_after` is in milliseconds. `reason` holds the underlying exception of a transport error.
  `body` is the decoded response body, if any.
  """

  @type t :: %__MODULE__{
          type: String.t(),
          message: String.t(),
          status: pos_integer() | nil,
          request_id: String.t() | nil,
          retry_after: non_neg_integer() | nil,
          reason: Exception.t() | nil,
          body: term()
        }

  defexception [:type, :message, :status, :request_id, :retry_after, :reason, :body]

  @doc false
  def from_response(%Req.Response{status: status} = response) do
    body = decode(response.body)

    {type, message} =
      case body do
        %{"error" => %{"type" => type, "message" => message}} -> {type, message}
        _other -> {"http_error", "HTTP #{status}"}
      end

    %__MODULE__{
      type: type,
      message: message,
      status: status,
      request_id: request_id(response, body),
      retry_after: Req.Response.get_retry_after(response),
      body: body
    }
  end

  # Endpoints that skip body decoding, such as downloads, still get JSON error bodies parsed.
  defp decode(body) when is_binary(body) do
    case JSON.decode(body) do
      {:ok, decoded} -> decoded
      {:error, _reason} -> body
    end
  end

  defp decode(body), do: body

  @doc false
  def from_exception(exception) do
    %__MODULE__{type: "transport_error", message: Exception.message(exception), reason: exception}
  end

  defp request_id(response, body) do
    case Req.Response.get_header(response, "request-id") do
      [id | _rest] -> id
      [] when is_map(body) -> body["request_id"]
      [] -> nil
    end
  end
end
