defmodule Intercom.ErrorTest do
  use ExUnit.Case
  alias Intercom.Error
  @request_id 12345

  describe "from_intercom_error" do
    test "not_found" do
      error_data = %{
        "code" => "not_found",
        "message" => "No such user_id[314159]"
      }
      error = Error.from_intercom_error(422, error_data, @request_id)
      assert error ==
        %Error{
          source: :intercom,
          code: :not_found,
          message: "No such user_id[314159]",
          request_id: @request_id,
          extra: %{}
        }
    end
  end
end
