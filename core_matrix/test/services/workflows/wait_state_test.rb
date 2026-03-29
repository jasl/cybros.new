require "test_helper"

class Workflows::WaitStateTest < ActiveSupport::TestCase
  test "ready attributes reset the workflow wait contract" do
    assert_equal(
      {
        wait_state: "ready",
        wait_reason_kind: nil,
        wait_reason_payload: {},
        waiting_since_at: nil,
        blocking_resource_type: nil,
        blocking_resource_id: nil,
      },
      Workflows::WaitState.ready_attributes
    )
  end
end
