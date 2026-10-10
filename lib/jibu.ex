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

  alias Jibu.Body
  alias Jibu.Error
  alias Jibu.Prompt
  alias Jibu.Response

  @base_url "https://api.anthropic.com"
  @api_version "2023-06-01"

  @doc """
  Builds a client as a `Req.Request`.

  ## Options

    * `:api_key` - defaults to the `ANTHROPIC_API_KEY` environment variable.
    * `:betas` - beta names sent in the `anthropic-beta` header.
    * `:base_url` - defaults to `#{@base_url}`.
    * `:model`, `:max_tokens` - defaults for `messages/2` bodies. `count_tokens/2` takes only the model.
    * `:defaults` - a map of further body defaults, for example `%{temperature: 0}`.

  A field set in a request body always wins over its default.

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
    {defaults, opts} = Keyword.pop(opts, :defaults, %{})
    {body_opts, opts} = Keyword.split(opts, [:model, :max_tokens])

    if api_key in [nil, ""] do
      raise ArgumentError, "pass :api_key or set ANTHROPIC_API_KEY"
    end

    beta_headers = if betas == [], do: [], else: [{"anthropic-beta", Enum.join(betas, ",")}]

    headers = [{"x-api-key", api_key}, {"anthropic-version", @api_version} | beta_headers]

    [base_url: @base_url, headers: headers, retry: &Jibu.Retry.retry/2]
    |> Req.new()
    |> Req.merge(opts)
    |> Req.Request.put_private(:jibu_defaults, Body.put_defaults(Map.new(body_opts), defaults))
  end

  @doc """
  Sends a Messages API request. The body is sent unchanged.
  """
  @spec messages(Req.Request.t(), map()) :: {:ok, Response.t()} | {:error, Error.t()}
  def messages(client, body) when is_map(body) do
    body = Body.put_defaults(body, defaults(client))

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
    # The endpoint rejects max_tokens and sampling fields, so only the model default applies.
    body = Body.put_defaults(body, Map.take(defaults(client), [:model, "model"]))
    request(client, :post, "/v1/messages/count_tokens", json: body)
  end

  @doc """
  Sends `prompt` as a user message and returns the text of the answer.

  `prompt` is a string or a list of content blocks, see `Jibu.Content`.

  ## Shortcuts

    * `:system` - the system prompt.
    * `:cache` - `true` marks the system prompt for prompt caching.
    * `:effort` - sets `output_config.effort`, for example `:low`.
    * `:messages` - an earlier conversation; `prompt` is appended to it.

  Every other keyword becomes a body field unchanged, for example `temperature: 0`.

  A refusal and output cut off at `max_tokens` or at the context window are errors.
  Use `messages/2` when you need the whole response.
  """
  @spec ask(Req.Request.t(), String.t() | [map()], keyword()) ::
          {:ok, String.t()} | {:error, Error.t()}
  def ask(client, prompt, opts \\ []) do
    with {:ok, response} <- messages(client, Prompt.body(prompt, opts)) do
      case Response.stop_error(response) do
        nil -> {:ok, Response.text(response)}
        error -> {:error, error}
      end
    end
  end

  @doc """
  Sends `prompt` with `schema` as structured output and returns the decoded JSON.

  Takes the same shortcuts as `ask/3`. See the [structured output guide](structured-output.md).
  """
  @spec extract(Req.Request.t(), String.t() | [map()], map(), keyword()) ::
          {:ok, term()} | {:error, Error.t()}
  def extract(client, prompt, schema, opts \\ []) do
    format = %{type: "json_schema", schema: schema}
    body = prompt |> Prompt.body(opts) |> Prompt.put_output_config(:format, format)

    with {:ok, response} <- messages(client, body), do: Response.json(response)
  end

  # Shared by every endpoint: runs the request inside a telemetry span and maps failures to
  # `Jibu.Error`.
  @doc false
  def request(client, method, path, opts) do
    metadata = %{method: method, path: path, model: Body.get(opts[:json], :model)}

    :telemetry.span([:jibu, :request], metadata, fn ->
      result = Req.request(client, [method: method, url: path] ++ opts)
      {normalize(result), Map.merge(metadata, stop_metadata(result))}
    end)
  end

  defp defaults(client), do: Req.Request.get_private(client, :jibu_defaults, %{})

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
