defmodule Intercom.Request do
  @moduledoc """
  A module for working with requests to the Intercom API.
  Requests are composed in a functional manner. The request does not happen
  until it is configured and passed to `make_request/1`.
  At a minimum, a request must have the endpoint and method specified to be
  valid.
  """
  alias Intercom.{API,Request}

  @type t :: %__MODULE__{
          endpoint: String.t() | nil,
          headers: map | nil,
          method: Intercom.API.method() | nil,
          opts: Keyword.t() | nil,
          params: map
        }

  defstruct opts: [],
            endpoint: nil,
            headers: nil,
            method: nil,
            params: %{}

  @doc """
  Creates a new request.
  Optionally accepts options for the request, such as using a specific API key.
  See `t:Intercom.options` for details.
  """
  @spec new_request(String.t(), Intercom.options(), map) :: t
  def new_request(api_key, opts \\ [], headers \\ %{}) do
    %Request{opts: Keyword.put_new(opts, :api_key, api_key), headers: headers}
  end

  @doc """
  Specifies an endpoint for the request.
  The endpoint should not include the `v1` prefix or an initial slash, for
  example `put_endpoint(request, "users")`.
  """
  @spec put_endpoint(t, String.t()) :: t
  def put_endpoint(%Request{} = request, endpoint) do
    %{request | endpoint: endpoint}
  end

  @doc """
  Specifies a method to use for the request.
  Accepts any of the standard HTTP methods as atoms, that is `:get`, `:post`,
  `:put`, `:patch` or `:delete`.
  """
  @spec put_method(t, Intercom.API.method()) :: t
  def put_method(%Request{} = request, method)
      when method in [:get, :post, :put, :patch, :delete] do
    %{request | method: method}
  end

  @doc """
  Specifies the parameters to be used for the request.
  If the request is a POST request, these are encoded in the request body.
  Otherwise, they are encoded in the URL.
  Calling this function multiple times will merge, not replace, the params
  currently specified.
  """
  @spec put_params(t, map) :: t
  def put_params(%Request{params: params} = request, new_params) do
    %{request | params: Map.merge(params, new_params)}
  end

  @doc """
  Specify a single param to be included in the request.
  """
  @spec put_param(t, atom, any) :: t
  def put_param(%Request{params: params} = request, key, value) do
    %{request | params: Map.put(params, key, value)}
  end

  @doc """
  Executes the request and returns the response.
  """
  @spec make_request(t) :: {:ok, map} | {:error, Intercom.Error.t()}
  def make_request(
        %Request{params: params, endpoint: endpoint, method: method, headers: headers, opts: opts}
      ) do
    API.request(params, method, endpoint, headers, opts)
  end
end
