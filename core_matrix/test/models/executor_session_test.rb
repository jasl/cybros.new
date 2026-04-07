require "test_helper"

class ExecutorSessionTest < ActiveSupport::TestCase
  test "allows only one active session per executor program" do
    installation = create_installation!
    executor_program = ExecutorProgram.create!(
      installation: installation,
      kind: "local",
      display_name: "Executor #{next_test_sequence}",
      executor_fingerprint: "executor-#{next_test_sequence}",
      connection_metadata: {},
      capability_payload: {},
      tool_catalog: [],
      lifecycle_state: "active"
    )

    ExecutorSession.create!(
      installation: installation,
      executor_program: executor_program,
      session_credential_digest: Digest::SHA256.hexdigest("credential-#{next_test_sequence}"),
      session_token_digest: Digest::SHA256.hexdigest("token-#{next_test_sequence}"),
      endpoint_metadata: {},
      lifecycle_state: "active"
    )

    conflicting = ExecutorSession.new(
      installation: installation,
      executor_program: executor_program,
      session_credential_digest: Digest::SHA256.hexdigest("credential-#{next_test_sequence}"),
      session_token_digest: Digest::SHA256.hexdigest("token-#{next_test_sequence}"),
      endpoint_metadata: {},
      lifecycle_state: "active"
    )

    assert_not conflicting.valid?
    assert_includes conflicting.errors[:executor_program_id], "already has an active session"
  end

  test "legacy execution helpers create executor-backed records" do
    installation = create_installation!
    executor_program = create_execution_runtime!(
      installation: installation,
      runtime_fingerprint: "helper-executor-#{next_test_sequence}"
    )

    executor_session = create_execution_session!(
      installation: installation,
      execution_runtime: executor_program
    )

    assert_instance_of ExecutorProgram, executor_program
    assert_instance_of ExecutorSession, executor_session
    assert_equal executor_program, executor_session.executor_program
  end
end
