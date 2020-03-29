defmodule Intercom.Error do
  @moduledoc """
  A struct which represents an error which occurred during a Intercom API call.

  https://developers.intercom.com/intercom-api-reference/reference#error-objects
  {
    "type": "error.list",
    "errors": [
      {
        "code": "not_found",
        "message": "No such user_id[314159]",
        "field": "user_id"
      },
      {
        "code": "not_found",
        "message": "No such email[pi@example.org]",
        "field": "email"
      }
    ]
  }
  """

  @type error_source :: :internal | :network | :intercom

  @type error_status ::
            :bad_request
          | :unauthorized
          | :request_failed
          | :not_found
          | :conflict
          | :too_many_requests
          | :server_error
          | :unknown_error

  @type intercom_error_type ::
            :server_error
          | :client_error
          | :type_mismatch
          | :not_found
          | :parameter_not_found
          | :parameter_invalid
          | :action_forbidden
          | :conflict
          | :api_plan_restricted
          | :rate_limit_exceeded
          | :unsupported
          | :token_revoked
          | :token_blocked
          | :token_not_found
          | :token_unauthorized
          | :token_expired
          | :missing_authorization
          | :retry_after
          | :job_closed
          | :not_restorable
          | :team_not_found
          | :team_unavailable
          | :admin_not_found

  @type t :: %__MODULE__{
          source: error_source,
          code: error_status | intercom_error_type | :network_error,
          request_id: String.t() | nil,
          message: String.t(),
          extra: %{
            optional(:param) => atom,
            optional(:http_status) => 400..599,
            optional(:raw_error) => map,
            optional(:hackney_reason) => any
          }
        }

  @enforce_keys [:source, :code, :message]
  defstruct [:source, :code, :request_id, :extra, :message, :user_message]

  @doc false
  @spec new(Keyword.t()) :: t
  def new(fields) do
    struct!(__MODULE__, fields)
  end

  @doc false
  @spec from_hackney_error(any) :: t
  def from_hackney_error(reason) do
    %__MODULE__{
      source: :network,
      code: :network_error,
      message:
        "An error occurred while making the network request. The HTTP client returned the following reason: #{
          inspect(reason)
        }",
      extra: %{
        hackney_reason: reason
      }
    }
  end

  @doc false
  @spec from_intercom_error(400..599, nil, String.t() | nil) :: t
  def from_intercom_error(status, nil, request_id) do
    %__MODULE__{
      source: :intercom,
      code: code_from_status(status),
      request_id: request_id,
      message: status |> message_from_status(),
      extra: %{http_status: status}
    }
  end

  @spec from_intercom_error(400..599, map, String.t()) :: t
  def from_intercom_error(_status, error_data, request_id) do
    %{"code" => code, "message" => message} = error_data
    %__MODULE__{
      source: :intercom,
      code: String.to_atom(code),
      request_id: request_id,
      message: message,
      extra: %{}
    }
  end

  defp code_from_status(400), do: :bad_request
  defp code_from_status(401), do: :unauthorized
  defp code_from_status(402), do: :request_failed
  defp code_from_status(404), do: :not_found
  defp code_from_status(409), do: :conflict
  defp code_from_status(429), do: :too_many_requests
  defp code_from_status(s) when s in [500, 502, 503, 504], do: :server_error
  defp code_from_status(_), do: :unknown_error

  defp message_from_status(400),
    do: "The request was unacceptable, often due to missing a required parameter."

  defp message_from_status(401), do: "No valid API key provided."
  defp message_from_status(402), do: "The parameters were valid but the request failed."
  defp message_from_status(404), do: "The requested resource doesn't exist."

  defp message_from_status(409),
    do:
      "The request conflicts with another request (perhaps due to using the same idempotent key)."

  defp message_from_status(429),
    do:
      "Too many requests hit the API too quickly. We recommend an exponential backoff of your requests."

  defp message_from_status(s) when s in [500, 502, 503, 504],
    do: "Something went wrong on Intercom's end."

  defp message_from_status(s), do: "An unknown HTTP code of #{s} was received."
end
