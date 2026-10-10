defmodule Jibu.Retry do
  @moduledoc false

  # Statuses the Anthropic SDKs retry, besides every 5xx. 529 is `overloaded_error`.
  @retry_statuses [408, 409, 429]
  @transport_reasons [:timeout, :econnrefused, :closed]

  # Req's `retry:` callback. `x-should-retry` from the API overrides the status rule.
  # A `retry-after` header sets the delay, unless the caller set `:retry_delay`.
  # Req rejects a `{:delay, ms}` answer when `:retry_delay` is set.
  def retry(request, %Req.Response{} = response) do
    case Req.Response.get_header(response, "x-should-retry") do
      ["true" | _rest] -> delay(request, response)
      ["false" | _rest] -> false
      [] -> retry_status?(response.status) and delay(request, response)
    end
  end

  def retry(_request, %Req.TransportError{reason: reason}), do: reason in @transport_reasons
  def retry(_request, _exception), do: false

  defp retry_status?(status), do: status in @retry_statuses or status >= 500

  defp delay(request, response) do
    with nil <- Req.Request.get_option(request, :retry_delay),
         ms when is_integer(ms) <- Req.Response.get_retry_after(response) do
      {:delay, ms}
    else
      _no_override -> true
    end
  end
end
