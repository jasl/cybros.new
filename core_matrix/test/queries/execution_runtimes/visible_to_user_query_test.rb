require "test_helper"

module ExecutionRuntimes
end

class ExecutionRuntimes::VisibleToUserQueryTest < ActiveSupport::TestCase
  test "returns active public runtimes plus the current users private runtimes" do
    installation = create_installation!
    user = create_user!(installation: installation, display_name: "Owner")
    other_user = create_user!(
      installation: installation,
      identity: create_identity!,
      display_name: "Other"
    )

    public_runtime = create_execution_runtime!(
      installation: installation,
      visibility: "public",
      display_name: "Public Runtime"
    )
    private_runtime = create_execution_runtime!(
      installation: installation,
      visibility: "private",
      owner_user: user,
      display_name: "Private Runtime"
    )
    create_execution_runtime!(
      installation: installation,
      visibility: "private",
      owner_user: other_user,
      display_name: "Other Users Runtime"
    )
    create_execution_runtime!(
      installation: installation,
      visibility: "public",
      display_name: "Retired Runtime",
      lifecycle_state: "retired"
    )

    result = ExecutionRuntimes::VisibleToUserQuery.call(user: user)

    assert_equal [public_runtime, private_runtime], result
  end
end
