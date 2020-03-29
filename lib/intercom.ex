defmodule Intercom do
  @moduledoc """
  A HTTP client for Intercom.

  ## Configuration

  Almost all of the requests that can be sent accept the following options:

    * `:api_key` - The Intercom API key to use for the request.
    * `:api_version` - The version of the api that is being used.
    * `:idempotency_key` - A string that is passed through as the "Idempotency-Key" header on all POST requests.

  ### HTTP Connection Pool

  Intercom is set up to use an HTTP connection pool by default. This
  means that it will reuse already opened HTTP connections in order to
  minimize the overhead of establishing connections. The pool is directly
  supervised by Intercom. Two configuration options are
  available to tune how this pool works: `:timeout` and `:max_connections`.

  `:timeout` is the amount of time that a connection will be allowed
  to remain open but idle (no data passing over it) before it is closed
  and cleaned up. This defaults to 5 seconds.

  `:max_connections` is the maximum number of connections that can be
  open at any time. This defaults to 10.

  Both these settings are located under the `:pool_options` key in
  your application configuration:

      config :intercom, :pool_options,
        timeout: 5_000,
        max_connections: 10

  If you prefer, you can also turn pooling off completely using
  the `:use_connection_pool` setting:

      config :intercom, use_connection_pool: false

  """
  use Application

  @type id :: String.t()
  @type date_query :: %{
          optional(:gt) => timestamp,
          optional(:gte) => timestamp,
          optional(:lt) => timestamp,
          optional(:lte) => timestamp
        }
  @type integer_query :: %{
          optional(:gt) => integer,
          optional(:gte) => integer,
          optional(:lt) => integer,
          optional(:lte) => integer
        }
  @type options :: Keyword.t()
  @type timestamp :: pos_integer

  @doc """
  Callback for the application

  Start the supervision tree including the supervised
  HTTP connection pool (if it's being used) when
  the VM loads the application pool.

  Note that we are taking advantage of the BEAM application
  standard in order to start the pool when the application is
  started. While we do start a supervisor, the supervisor is only
  to comply with the expectations of the BEAM application standard.
  It is not given any children to supervise.
  """
  @spec start(Application.start_type(), any) :: {:error, any} | {:ok, pid} | {:ok, pid, any}
  def start(_start_type, _args) do
    import Supervisor.Spec, warn: false

    children = Intercom.API.supervisor_children()

    opts = [strategy: :one_for_one, name: Intercom.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
