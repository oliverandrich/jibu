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

  alias Jibu.Accumulator
  alias Jibu.Body
  alias Jibu.Error
  alias Jibu.Prompt
  alias Jibu.Response
  alias Jibu.SSE

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
  Sends a Messages API request as a stream and calls `fun` with each event.

  Jibu sets `stream: true` and sends the body otherwise unchanged.
  `fun` receives every server-sent event as a decoded map, including `ping` and unknown types.
  The result is the assembled message as a `Jibu.Response`.

  An `error` event returns `{:error, %Jibu.Error{}}` with the partial message in `body`.
  Jibu does not retry once events have arrived when `:retry` is a function.
  See the [streaming guide](streaming.md).
  """
  @spec stream(Req.Request.t(), map(), (map() -> any())) ::
          {:ok, Response.t()} | {:error, Error.t()}
  def stream(client, body, fun) when is_map(body) and is_function(fun, 1) do
    {stream_key, _stream} = Body.fetch(body, :stream, nil)

    body =
      body
      |> Map.drop([:stream, "stream"])
      |> Body.put_defaults(defaults(client))
      |> Map.put(stream_key, true)

    # The into callback and the steps run in the calling process. The process dictionary keeps
    # the stream state when a transport error drops the response.
    key = {__MODULE__, :stream, make_ref()}

    client =
      client
      |> no_retry_after_events(key)
      |> Req.Request.append_response_steps(jibu_stream: &finish_stream(&1, key))

    try do
      case request(client, :post, "/v1/messages", json: body, into: stream_into(fun, key)) do
        {:ok, message} ->
          {:ok, Response.new(message)}

        {:error, %Error{type: "transport_error"} = error} ->
          {:error, %{error | body: partial(key)}}

        {:error, error} ->
          {:error, error}
      end
    after
      Process.delete(key)
    end
  end

  # A retry after streamed events would pass them to `fun` a second time.
  defp no_retry_after_events(client, key) do
    case Req.Request.get_option(client, :retry) do
      retry when is_function(retry, 2) ->
        Req.Request.put_option(client, :retry, fn request, result ->
          Process.get(key) == nil and retry.(request, result)
        end)

      _other ->
        client
    end
  end

  # Error bodies stay raw: `Error.from_response/1` decodes them.
  defp stream_into(fun, key) do
    fn {:data, chunk}, {request, response} ->
      if response.status in 200..299 and event_stream?(response) do
        state = Process.get(key, {SSE.new(), Accumulator.new(), nil})
        Process.put(key, stream_chunk(state, chunk, fun, response))
        {:cont, {request, response}}
      else
        {:cont, {request, %{response | body: response.body <> chunk}}}
      end
    end
  end

  defp event_stream?(response) do
    response
    |> Req.Response.get_header("content-type")
    |> Enum.any?(&String.starts_with?(&1, "text/event-stream"))
  end

  defp stream_chunk({sse, acc, error}, chunk, fun, response) do
    {events, sse} = SSE.parse(sse, chunk)
    {acc, error} = Enum.reduce(events, {acc, error}, &stream_event(&1, &2, fun, response))
    {sse, acc, error}
  end

  # The API ends a stream after an error event. Anything after the first error is ignored.
  defp stream_event(_event, {_acc, %Error{}} = state, _fun, _response), do: state

  defp stream_event(%{data: data}, {acc, nil}, fun, response) do
    case JSON.decode(data) do
      {:ok, %{"type" => "error"} = event} ->
        fun.(event)
        {acc, Error.from_response(%{response | body: event})}

      {:ok, event} ->
        fun.(event)
        {Accumulator.add(acc, event), nil}

      {:error, reason} ->
        message = "the event data is not valid JSON: #{inspect(reason)}"
        {acc, %{Error.from_response(response) | type: "invalid_json", message: message}}
    end
  end

  # Puts the assembled message into the body, so telemetry and errors see it.
  defp finish_stream({request, %Req.Response{status: status} = response}, key)
       when status in 200..299 do
    case Process.get(key) do
      {_sse, _acc, error} ->
        message = partial(key)
        error = error && %{error | body: message}

        {request,
         response |> Map.put(:body, message) |> Req.Response.put_private(:jibu_error, error)}

      nil ->
        error = %{
          Error.from_response(response)
          | type: "invalid_stream",
            message: "the response is not an event stream"
        }

        {request, Req.Response.put_private(response, :jibu_error, error)}
    end
  end

  defp finish_stream(request_response, _key), do: request_response

  defp partial(key) do
    case Process.get(key) do
      {_sse, acc, _error} -> Accumulator.message(acc)
      nil -> nil
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
    * `:on_text` - a function that receives each piece of text as it streams in.
      The answer then goes through `stream/3`.

  Every other keyword becomes a body field unchanged, for example `temperature: 0`.

  A refusal and output cut off at `max_tokens` or at the context window are errors.
  Use `messages/2` when you need the whole response.
  """
  @spec ask(Req.Request.t(), String.t() | [map()], keyword()) ::
          {:ok, String.t()} | {:error, Error.t()}
  def ask(client, prompt, opts \\ []) do
    {on_text, opts} = Keyword.pop(opts, :on_text)

    with {:ok, response} <- send_prompt(client, Prompt.body(prompt, opts), on_text) do
      case Response.stop_error(response) do
        nil -> {:ok, Response.text(response)}
        error -> {:error, error}
      end
    end
  end

  defp send_prompt(client, body, nil), do: messages(client, body)

  defp send_prompt(client, body, on_text) when is_function(on_text, 1),
    do: stream(client, body, &forward_text(&1, on_text))

  defp send_prompt(_client, _body, on_text),
    do:
      raise(
        ArgumentError,
        "on_text: must be a function of one argument, got: #{inspect(on_text)}"
      )

  defp forward_text(%{"delta" => %{"type" => "text_delta", "text" => text}}, on_text),
    do: on_text.(text)

  defp forward_text(_event, _on_text), do: :ok

  @doc """
  Sends `prompt` with `schema` as structured output and returns the decoded JSON.

  Takes the shortcuts of `ask/3` except `:on_text`.
  See the [structured output guide](structured-output.md).
  """
  @spec extract(Req.Request.t(), String.t() | [map()], map(), keyword()) ::
          {:ok, term()} | {:error, Error.t()}
  def extract(client, prompt, schema, opts \\ []) do
    format = %{type: "json_schema", schema: schema}
    body = prompt |> Prompt.body(opts) |> Prompt.put_output_config(:format, format)

    with {:ok, response} <- messages(client, body), do: Response.json(response)
  end

  # Shared by every endpoint: runs the request inside a telemetry span and maps failures to
  # `Jibu.Error`. A response step can fail a 2xx response by setting the private `:jibu_error`.
  @doc false
  def request(client, method, path, opts) do
    metadata = %{method: method, path: path, model: Body.get(opts[:json], :model)}

    :telemetry.span([:jibu, :request], metadata, fn ->
      result = Req.request(client, [method: method, url: path] ++ opts)
      {normalize(result), Map.merge(metadata, stop_metadata(result))}
    end)
  end

  defp defaults(client), do: Req.Request.get_private(client, :jibu_defaults, %{})

  defp normalize({:ok, %Req.Response{status: status, body: body} = response})
       when status in 200..299 do
    case Req.Response.get_private(response, :jibu_error) do
      nil -> {:ok, body}
      error -> {:error, error}
    end
  end

  defp normalize({:ok, %Req.Response{} = response}), do: {:error, Error.from_response(response)}
  defp normalize({:error, exception}), do: {:error, Error.from_exception(exception)}

  defp stop_metadata({:ok, %Req.Response{status: status, body: body}}),
    do: %{status: status, usage: usage(body)}

  defp stop_metadata({:error, _exception}), do: %{status: nil, usage: nil}

  defp usage(%{"usage" => usage}), do: usage
  defp usage(_body), do: nil
end
