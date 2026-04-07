require "test_helper"

class ExecutorProgramTest < ActiveSupport::TestCase
  test "generates and resolves a public id" do
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

    assert executor_program.public_id.present?
    assert_equal executor_program, ExecutorProgram.find_by_public_id!(executor_program.public_id)
  end

  test "tracks kind, display_name, and connection metadata" do
    installation = create_installation!
    executor_program = ExecutorProgram.create!(
      installation: installation,
      kind: "container",
      display_name: "GPU Node A",
      executor_fingerprint: "gpu-node-a",
      connection_metadata: {
        "transport" => "http",
        "base_url" => "https://agents.example.test",
      },
      capability_payload: {},
      tool_catalog: [],
      lifecycle_state: "active"
    )

    assert executor_program.container?
    assert_equal "GPU Node A", executor_program.display_name
    assert_equal "https://agents.example.test", executor_program.connection_metadata["base_url"]

    invalid_program = ExecutorProgram.new(
      installation: installation,
      kind: "local",
      display_name: "Broken Executor",
      executor_fingerprint: "broken-executor",
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
    ExecutorProgram.create!(
      installation: installation,
      kind: "local",
      display_name: "Executor A",
      executor_fingerprint: "executor-a",
      connection_metadata: {},
      capability_payload: { "supports_process_runs" => true },
      tool_catalog: [],
      lifecycle_state: "active"
    )

    duplicate = ExecutorProgram.new(
      installation: installation,
      kind: "local",
      display_name: "Duplicate Executor",
      executor_fingerprint: "executor-a",
      connection_metadata: {},
      capability_payload: {},
      tool_catalog: [],
      lifecycle_state: "active"
    )
    invalid_payload = ExecutorProgram.new(
      installation: installation,
      kind: "local",
      display_name: "Invalid Payload",
      executor_fingerprint: "executor-b",
      connection_metadata: {},
      capability_payload: [],
      tool_catalog: [],
      lifecycle_state: "active"
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:executor_fingerprint], "has already been taken"
    assert_not invalid_payload.valid?
    assert_includes invalid_payload.errors[:capability_payload], "must be a Hash"
  end
end
