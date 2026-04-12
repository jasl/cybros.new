require "test_helper"

class ExecutionRuntimeConnectionTest < ActiveSupport::TestCase
  test "allows only one active connection per execution runtime" do
    installation = create_installation!
    execution_runtime = create_execution_runtime!(installation: installation)
    execution_runtime_version = create_execution_runtime_version!(
      installation: installation,
      execution_runtime: execution_runtime
    )

    ExecutionRuntimeConnection.create!(
      installation: installation,
      execution_runtime: execution_runtime,
      execution_runtime_version: execution_runtime_version,
      connection_credential_digest: Digest::SHA256.hexdigest("credential-#{next_test_sequence}"),
      connection_token_digest: Digest::SHA256.hexdigest("token-#{next_test_sequence}"),
      endpoint_metadata: {},
      lifecycle_state: "active"
    )

    conflicting = ExecutionRuntimeConnection.new(
      installation: installation,
      execution_runtime: execution_runtime,
      execution_runtime_version: execution_runtime_version,
      connection_credential_digest: Digest::SHA256.hexdigest("credential-#{next_test_sequence}"),
      connection_token_digest: Digest::SHA256.hexdigest("token-#{next_test_sequence}"),
      endpoint_metadata: {},
      lifecycle_state: "active"
    )

    assert_not conflicting.valid?
    assert_includes conflicting.errors[:execution_runtime_id], "already has an active connection"
  end

  test "legacy execution helpers create executor-backed records" do
    installation = create_installation!
    execution_runtime = create_execution_runtime!(installation: installation)
    execution_runtime_version = create_execution_runtime_version!(
      installation: installation,
      execution_runtime: execution_runtime
    )

    execution_runtime_connection = create_execution_runtime_connection!(
      installation: installation,
      execution_runtime: execution_runtime,
      execution_runtime_version: execution_runtime_version
    )

    assert_instance_of ExecutionRuntime, execution_runtime
    assert_instance_of ExecutionRuntimeConnection, execution_runtime_connection
    assert_equal execution_runtime, execution_runtime_connection.execution_runtime
    assert_equal execution_runtime_version, execution_runtime_connection.execution_runtime_version
  end
end
