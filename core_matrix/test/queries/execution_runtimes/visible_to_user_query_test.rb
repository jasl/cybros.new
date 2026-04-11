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

    public_runtime = ExecutionRuntime.create!(
      installation: installation,
      visibility: "public",
      provisioning_origin: "system",
      kind: "local",
      display_name: "Public Runtime",
      execution_runtime_fingerprint: "public-runtime",
      connection_metadata: {},
      capability_payload: {},
      tool_catalog: [],
      lifecycle_state: "active"
    )
    private_runtime = ExecutionRuntime.create!(
      installation: installation,
      visibility: "private",
      provisioning_origin: "user_created",
      owner_user: user,
      kind: "local",
      display_name: "Private Runtime",
      execution_runtime_fingerprint: "private-runtime",
      connection_metadata: {},
      capability_payload: {},
      tool_catalog: [],
      lifecycle_state: "active"
    )
    ExecutionRuntime.create!(
      installation: installation,
      visibility: "private",
      provisioning_origin: "user_created",
      owner_user: other_user,
      kind: "local",
      display_name: "Other Users Runtime",
      execution_runtime_fingerprint: "other-users-runtime",
      connection_metadata: {},
      capability_payload: {},
      tool_catalog: [],
      lifecycle_state: "active"
    )
    ExecutionRuntime.create!(
      installation: installation,
      visibility: "public",
      provisioning_origin: "system",
      kind: "local",
      display_name: "Retired Runtime",
      execution_runtime_fingerprint: "retired-runtime",
      connection_metadata: {},
      capability_payload: {},
      tool_catalog: [],
      lifecycle_state: "retired"
    )

    result = ExecutionRuntimes::VisibleToUserQuery.call(user: user)

    assert_equal [public_runtime, private_runtime], result
  end
end
