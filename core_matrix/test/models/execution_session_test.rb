require "test_helper"

class ExecutionSessionTest < ActiveSupport::TestCase
  test "allows only one active session per execution runtime" do
    installation = create_installation!
    execution_runtime = create_execution_runtime!(installation: installation)

    create_execution_session!(
      installation: installation,
      execution_runtime: execution_runtime,
      lifecycle_state: "active"
    )

    conflicting = ExecutionSession.new(
      installation: installation,
      execution_runtime: execution_runtime,
      session_credential_digest: Digest::SHA256.hexdigest("credential-#{next_test_sequence}"),
      session_token_digest: Digest::SHA256.hexdigest("token-#{next_test_sequence}"),
      endpoint_metadata: {},
      lifecycle_state: "active"
    )

    assert_not conflicting.valid?
    assert_includes conflicting.errors[:execution_runtime_id], "already has an active session"
  end
end
