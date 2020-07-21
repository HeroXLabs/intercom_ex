defmodule Intercom.API do
  @moduledoc """
  Low-level utilities for interacting with the Intercom API.
  """
  alias Intercom.{Config, Error}
  require Logger

  @type method :: :get | :post | :put | :delete | :patch
  @type headers :: %{String.t() => String.t()} | %{}
  @type body :: iodata() | {:multipart, list()}
  @typep http_success :: {:ok, integer, [{String.t(), String.t()}], String.t()}
  @typep http_failure :: {:error, term}

  @pool_name __MODULE__
  @api_version "2020-03-28"

  @idempotency_key_header "Idempotency-Key"

  @default_max_attempts 3
  @default_base_backoff 500
  @default_max_backoff 2_000

  @spec json_library() :: module
  def json_library() do
    Config.resolve(:json_library, Jason)
  end

  def supervisor_children do
    if use_pool?() do
      [:hackney_pool.child_spec(@pool_name, get_pool_options())]
    else
      []
    end
  end

  @spec get_pool_options() :: Keyword.t()
  defp get_pool_options() do
    Config.resolve(:pool_options)
  end

  @spec get_base_url() :: String.t()
  defp get_base_url() do
    Config.resolve(:api_base_url)
  end

  @spec use_pool?() :: boolean
  defp use_pool?() do
    Config.resolve(:use_connection_pool)
  end

  @spec http_module() :: module
  defp http_module() do
    Config.resolve(:http_module, :hackney)
  end

  @spec retry_config() :: Keyword.t()
  defp retry_config() do
    Config.resolve(:retries, [])
  end

  @doc """
  Checks if an error is a problem that we should retry on. This includes both
  socket errors that may represent an intermittent problem and some special
  HTTP statuses.
  """
  @spec should_retry?(
          http_success | http_failure,
          attempts :: non_neg_integer,
          config :: Keyword.t()
        ) :: boolean
  def should_retry?(response, attempts \\ 0, config \\ []) do
    max_attempts = Keyword.get(config, :max_attempts) || @default_max_attempts

    if attempts >= max_attempts do
      false
    else
      retry_response?(response)
    end
  end

  @doc """
  A low level utility function to generate a new idempotency key for
  `#{@idempotency_key_header}` request header value.
  """
  @spec generate_idempotency_key() :: binary
  def generate_idempotency_key do
    binary = <<
      System.system_time(:nanosecond)::64,
      :erlang.phash2({node(), self()}, 16_777_216)::24,
      System.unique_integer([:positive])::32
    >>

    Base.hex_encode32(binary, case: :lower, padding: false)
  end

  @spec add_common_headers(headers) :: headers
  defp add_common_headers(existing_headers) do
    Map.merge(existing_headers, %{
      "Accept" => "application/json; charset=utf8",
      "Accept-Encoding" => "gzip",
      "Connection" => "keep-alive"
    })
  end

  @spec add_default_headers(headers) :: headers
  defp add_default_headers(existing_headers) do
    existing_headers = add_common_headers(existing_headers)

    case Map.has_key?(existing_headers, "Content-Type") do
      false -> existing_headers |> Map.put("Content-Type", "application/x-www-form-urlencoded")
      true -> existing_headers
    end
  end

  @spec add_idempotency_headers(headers, method) :: headers
  defp add_idempotency_headers(existing_headers, method) when method in [:get, :head] do
    existing_headers
  end

  defp add_idempotency_headers(existing_headers, _method) do
    # By using `Map.put_new/3` instead of `Map.put/3`, we allow users to
    # provide their own idempotency key.
    existing_headers
    |> Map.put_new(@idempotency_key_header, generate_idempotency_key())
  end

  @spec add_auth_header(headers, String.t()) :: headers
  defp add_auth_header(existing_headers, api_key) do
    Map.put(existing_headers, "Authorization", "Bearer #{api_key}")
  end

  @spec add_api_version(headers, String.t() | nil) :: headers
  defp add_api_version(existing_headers, nil), do: add_api_version(existing_headers, @api_version)

  defp add_api_version(existing_headers, api_version) do
    Map.merge(existing_headers, %{
      "User-Agent" => "Alvis/v1 alvis/#{api_version}",
      "Alvis-Version" => api_version
    })
  end

  @spec add_default_options(list) :: list
  defp add_default_options(opts) do
    [:with_body | opts]
  end

  @spec add_pool_option(list) :: list
  defp add_pool_option(opts) do
    if use_pool?() do
      [{:pool, @pool_name} | opts]
    else
      opts
    end
  end

  @spec add_options_from_config(list) :: list
  defp add_options_from_config(opts) do
    if is_list(Intercom.Config.resolve(:hackney_opts)) do
      opts ++ Intercom.Config.resolve(:hackney_opts)
    else
      opts
    end
  end

  @doc """
  A low level utility function to make a direct request to the Intercom API
  ## Setting the api key
      request(%{}, :get, "/customers", %{}, api_key: "bogus key")
  ## Setting api version
  The api version defaults to #{@api_version} but a custom version can be passed
  in as follows:
      request(%{}, :get, "/customers", %{}, api_version: "2018-11-04")
  ## Connect Accounts
  If you'd like to make a request on behalf of another Intercom account
  utilizing the Connect program, you can pass the other Intercom account's
  ID to the request function as follows:
      request(%{}, :get, "/customers", %{}, connect_account: "acc_134151")
  """
  @spec request(body, method, String.t(), headers, list) ::
          {:ok, Map.t()} | {:error, Intercom.Error.t()}
  def request(body, :get, endpoint, headers, opts) do
    base_url = get_base_url()

    req_url =
      body
      |> Intercom.Util.map_keys_to_atoms()
      |> Intercom.Util.encode_query()
      |> prepend_url("#{base_url}#{endpoint}")

    perform_request(req_url, :get, "", headers, opts)
  end

  def request(body, method, endpoint, headers, opts) do
    {idempotency_key, opts} = Keyword.pop(opts, :idempotency_key)

    base_url = get_base_url()
    req_url = "#{base_url}#{endpoint}"
    headers = add_idempotency_header(idempotency_key, headers, method)

    req_body =
      case Map.get(headers, "Content-Type") do
        "application/json" ->
          body
          |> json_library().encode!()
        _ ->
          body
          |> Intercom.Util.map_keys_to_atoms()
          |> Intercom.Util.encode_query()
      end

    Logger.debug "Intercom.API#perform_request \nheaders\n#{inspect headers}\nbody\n#{inspect req_body}\n"

    perform_request(req_url, method, req_body, headers, opts)
  end

  @spec perform_request(String.t(), method, body, headers, list) ::
          {:ok, map} | {:error, Intercom.Error.t()}
  defp perform_request(req_url, method, body, headers, opts) do
    {api_version, opts} = Keyword.pop(opts, :api_version)
    {api_key, opts} = Keyword.pop(opts, :api_key)

    req_headers =
      headers
      |> add_default_headers()
      |> add_auth_header(api_key)
      |> add_api_version(api_version)
      |> add_idempotency_headers(method)
      |> Map.to_list()

    req_opts =
      opts
      |> add_default_options()
      |> add_pool_option()
      |> add_options_from_config()

    do_perform_request(method, req_url, req_headers, body, req_opts)
  end

  @spec do_perform_request(method, String.t(), [headers], body, list) ::
          {:ok, map} | {:error, Intercom.Error.t()}
  defp do_perform_request(method, url, headers, body, opts) do
    do_perform_request_and_retry(method, url, headers, body, opts, {:attempts, 0})
  end

  @spec do_perform_request_and_retry(
          method,
          String.t(),
          [headers],
          body,
          list,
          {:attempts, non_neg_integer} | {:response, http_success | http_failure}
        ) :: {:ok, map} | {:error, Intercom.Error.t()}
  defp do_perform_request_and_retry(_method, _url, _headers, _body, _opts, {:response, response}) do
    handle_response(response)
  end

  defp do_perform_request_and_retry(method, url, headers, body, opts, {:attempts, attempts}) do
    response = http_module().request(method, url, headers, body, opts)

    do_perform_request_and_retry(
      method,
      url,
      headers,
      body,
      opts,
      add_attempts(response, attempts, retry_config())
    )
  end

  @spec add_attempts(http_success | http_failure, non_neg_integer, Keyword.t()) ::
          {:attempts, non_neg_integer} | {:response, http_success | http_failure}
  defp add_attempts(response, attempts, retry_config) do
    if should_retry?(response, attempts, retry_config) do
      backoff_in_milli_seconds = backoff(attempts, retry_config)

      Logger.debug "Intercom api client will retry attempt (#{attempts + 1}) in #{backoff_in_milli_seconds / 1000}"

      :timer.sleep(backoff_in_milli_seconds)

      {:attempts, attempts + 1}
    else
      {:response, response}
    end
  end

  @doc """
  Returns backoff in milliseconds.
  """
  @spec backoff(attempts :: non_neg_integer, config :: Keyword.t()) :: non_neg_integer
  def backoff(attempts, config) do
    base_backoff = Keyword.get(config, :base_backoff) || @default_base_backoff
    max_backoff = Keyword.get(config, :max_backoff) || @default_max_backoff

    (base_backoff * :math.pow(2, attempts))
    |> min(max_backoff)
    |> backoff_jitter()
    |> max(base_backoff)
    |> trunc()
  end

  @spec backoff_jitter(float) :: float
  defp backoff_jitter(n) do
    # Apply some jitter by randomizing the value in the range of (n / 2) to n
    n * (0.5 * (1 + :rand.uniform()))
  end

  # https://developers.intercom.com/intercom-api-reference/reference#http-responses
  @spec retry_response?(http_success | http_failure) :: boolean
  # 409 conflict
  defp retry_response?({:ok, 409, _headers, _body}), do: true
  # 429 too many requests
  defp retry_response?({:ok, 429, _headers, _body}), do: true
  defp retry_response?({:ok, 503, _headers, _body}), do: true

  # Destination refused the connection, the connection was reset, or a
  # variety of other connection failures. This could occur from a single
  # saturated server, so retry in case it's intermittent.
  defp retry_response?({:error, :econnrefused}), do: true
  # Retry on timeout-related problems (either on open or read).
  defp retry_response?({:error, :connect_timeout}), do: true
  defp retry_response?({:error, :timeout}), do: true
  # Retry on Intercom service unavailable, which also has status 503
  defp retry_response?({:error, :service_unavailable}), do: true
  defp retry_response?({:error, :too_many_requests}), do: true
  defp retry_response?({:error, error}) do
    Logger.error "Intercom api client error: #{inspect error}"
    false
  end

  defp retry_response?(_response), do: false

  @spec handle_response(http_success | http_failure) :: {:ok, map} | {:error, Intercom.Error.t()}
  defp handle_response({:ok, status, headers, body}) when status >= 200 and status <= 299 do
    decoded_body =
      body
      |> decompress_body(headers)
      |> json_library().decode!()

    {:ok, decoded_body}
  end

  defp handle_response({:ok, status, headers, body}) when status >= 300 and status <= 599 do
    request_id = headers |> List.keyfind("Request-Id", 0)

    error =
      case json_library().decode(body) do
        {:ok, %{"errors" => api_errors}} ->
          api_error = api_errors |> List.first()
          Error.from_intercom_error(status, api_error, request_id)
        _ ->
          # e.g. if the body is empty
          Error.from_intercom_error(status, nil, request_id)
      end

    {:error, error}
  end

  defp handle_response({:error, reason}) do
    error = Error.from_hackney_error(reason)
    {:error, error}
  end

  defp decompress_body(body, headers) do
    headers_dict = :hackney_headers.new(headers)

    case :hackney_headers.get_value("Content-Encoding", headers_dict) do
      "gzip" -> :zlib.gunzip(body)
      "deflate" -> :zlib.unzip(body)
      _ -> body
    end
  end

  defp prepend_url("", url), do: url
  defp prepend_url(query, url), do: "#{url}?#{query}"

  defp add_idempotency_header(nil, headers, _), do: headers

  defp add_idempotency_header(idempotency_key, headers, :post) do
    Map.put(headers, "Idempotency-Key", idempotency_key)
  end

  defp add_idempotency_header(_, headers, _), do: headers
end
