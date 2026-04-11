require "test_helper"

class ExecutionRuntimeTest < ActiveSupport::TestCase
  test "generates and resolves a public id" do
    installation = create_installation!
    execution_runtime = ExecutionRuntime.create!(
      installation: installation,
      kind: "local",
      display_name: "Executor #{next_test_sequence}",
      execution_runtime_fingerprint: "executor-#{next_test_sequence}",
      connection_metadata: {},
      capability_payload: {},
      tool_catalog: [],
      lifecycle_state: "active"
    )

    assert execution_runtime.public_id.present?
    assert_equal execution_runtime, ExecutionRuntime.find_by_public_id!(execution_runtime.public_id)
  end

  test "tracks kind, display_name, and connection metadata" do
    installation = create_installation!
    execution_runtime = ExecutionRuntime.create!(
      installation: installation,
      kind: "container",
      display_name: "GPU Node A",
      execution_runtime_fingerprint: "gpu-node-a",
      connection_metadata: {
        "transport" => "http",
        "base_url" => "https://agents.example.test",
      },
      capability_payload: {},
      tool_catalog: [],
      lifecycle_state: "active"
    )

    assert execution_runtime.container?
    assert_equal "GPU Node A", execution_runtime.display_name
    assert_equal "https://agents.example.test", execution_runtime.connection_metadata["base_url"]

    invalid_program = ExecutionRuntime.new(
      installation: installation,
      kind: "local",
      display_name: "Broken Executor",
      execution_runtime_fingerprint: "broken-executor",
      connection_metadata: [],
      capability_payload: {},
      tool_catalog: [],
      lifecycle_state: "active"
    )

    assert_not invalid_program.valid?
    assert_includes invalid_program.errors[:connection_metadata], "must be a Hash"
  end

  test "requires an installation-local executor fingerprint and capability payload hash" do
    installation = create_installation!
    ExecutionRuntime.create!(
      installation: installation,
      kind: "local",
      display_name: "Executor A",
      execution_runtime_fingerprint: "executor-a",
      connection_metadata: {},
      capability_payload: { "supports_process_runs" => true },
      tool_catalog: [],
      lifecycle_state: "active"
    )

    duplicate = ExecutionRuntime.new(
      installation: installation,
      kind: "local",
      display_name: "Duplicate Executor",
      execution_runtime_fingerprint: "executor-a",
      connection_metadata: {},
      capability_payload: {},
      tool_catalog: [],
      lifecycle_state: "active"
    )
    invalid_payload = ExecutionRuntime.new(
      installation: installation,
      kind: "local",
      display_name: "Invalid Payload",
      execution_runtime_fingerprint: "executor-b",
      connection_metadata: {},
      capability_payload: [],
      tool_catalog: [],
      lifecycle_state: "active"
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:execution_runtime_fingerprint], "has already been taken"
    assert_not invalid_payload.valid?
    assert_includes invalid_payload.errors[:capability_payload], "must be a Hash"
  end
end
