defmodule Jibu do
  @moduledoc """
  A thin client for the Anthropic API, built on Req.

  Request bodies are plain maps, sent unchanged.
  Jibu has no model list and no parameter schema.
  New API fields therefore work without a new release.

      client = Jibu.new(api_key: System.fetch_env!("ANTHROPIC_API_KEY"))

      {:ok, response} =
        Jibu.messages(client, %{
          model: "claude-opus-5-5",
          max_tokens: 1024,
          messages: [%{role: "user", content: "Hello"}]
        })

      Jibu.Response.text(response)

  Start with the [Getting started guide](getting-started.md).
  """

  alias Jibu.Error
  alias Jibu.Response

  @base_url "https://api.anthropic.com"
  @api_version "2023-06-01"

  @doc """
  Builds a client as a `Req.Request`.

  ## Options

    * `:api_key` - defaults to the `ANTHROPIC_API_KEY` environment variable.
    * `:betas` - beta names sent in the `anthropic-beta` header.
    * `:base_url` - defaults to `#{@base_url}`.

  Every other option goes to `Req.merge/2`, for example `:receive_timeout`, `:headers`
  or `plug: {Req.Test, MyStub}`. Headers merge by name with the API headers.

  Jibu retries transient failures. Pass `retry: false` to turn that off.
  The [errors guide](errors.md) lists the rules.
  """
  @spec new(keyword()) :: Req.Request.t()
  def new(opts \\ []) do
    {api_key, opts} =
      Keyword.pop_lazy(opts, :api_key, fn -> System.get_env("ANTHROPIC_API_KEY") end)

    {betas, opts} = Keyword.pop(opts, :betas, [])

    if api_key in [nil, ""] do
      raise ArgumentError, "pass :api_key or set ANTHROPIC_API_KEY"
    end

    beta_headers = if betas == [], do: [], else: [{"anthropic-beta", Enum.join(betas, ",")}]

    headers = [{"x-api-key", api_key}, {"anthropic-version", @api_version} | beta_headers]

    [base_url: @base_url, headers: headers, retry: &Jibu.Retry.retry/2]
    |> Req.new()
    |> Req.merge(opts)
  end

  @doc """
  Sends a Messages API request. The body is sent unchanged.
  """
  @spec messages(Req.Request.t(), map()) :: {:ok, Response.t()} | {:error, Error.t()}
  def messages(client, body) when is_map(body) do
    with {:ok, response_body} <- request(client, :post, "/v1/messages", json: body) do
      {:ok, Response.new(response_body)}
    end
  end

  @doc """
  Counts the input tokens of a Messages API request body. The body is sent unchanged.
  The API does not bill this call.
  """
  @spec count_tokens(Req.Request.t(), map()) :: {:ok, map()} | {:error, Error.t()}
  def count_tokens(client, body) when is_map(body) do
    request(client, :post, "/v1/messages/count_tokens", json: body)
  end

  # Shared by every endpoint: runs the request inside a telemetry span and maps failures to
  # `Jibu.Error`.
  @doc false
  def request(client, method, path, opts) do
    metadata = %{method: method, path: path, model: Jibu.Body.get(opts[:json], :model)}

    :telemetry.span([:jibu, :request], metadata, fn ->
      result = Req.request(client, [method: method, url: path] ++ opts)
      {normalize(result), Map.merge(metadata, stop_metadata(result))}
    end)
  end

  defp normalize({:ok, %Req.Response{status: status, body: body}}) when status in 200..299,
    do: {:ok, body}

  defp normalize({:ok, %Req.Response{} = response}), do: {:error, Error.from_response(response)}
  defp normalize({:error, exception}), do: {:error, Error.from_exception(exception)}

  defp stop_metadata({:ok, %Req.Response{status: status, body: body}}),
    do: %{status: status, usage: usage(body)}

  defp stop_metadata({:error, _exception}), do: %{status: nil, usage: nil}

  defp usage(%{"usage" => usage}), do: usage
  defp usage(_body), do: nil
end
