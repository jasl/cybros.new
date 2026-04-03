require "test_helper"

class ExecutionRuntimeTest < ActiveSupport::TestCase
  test "generates and resolves a public id" do
    execution_runtime = create_execution_runtime!

    assert execution_runtime.public_id.present?
    assert_equal execution_runtime, ExecutionRuntime.find_by_public_id!(execution_runtime.public_id)
  end

  test "tracks kind, display_name, and connection metadata" do
    installation = create_installation!
    execution_runtime = create_execution_runtime!(
      installation: installation,
      kind: "container",
      display_name: "GPU Node A",
      connection_metadata: {
        "transport" => "http",
        "base_url" => "https://agents.example.test",
      }
    )

    assert execution_runtime.container?
    assert_equal "GPU Node A", execution_runtime.display_name
    assert_equal "https://agents.example.test", execution_runtime.connection_metadata["base_url"]

    invalid_runtime = ExecutionRuntime.new(
      installation: installation,
      kind: "local",
      display_name: "Broken Runtime",
      connection_metadata: []
    )

    assert_not invalid_runtime.valid?
    assert_includes invalid_runtime.errors[:connection_metadata], "must be a Hash"
  end

  test "requires an installation-local runtime fingerprint and capability payload hash" do
    installation = create_installation!
    create_execution_runtime!(
      installation: installation,
      runtime_fingerprint: "runtime-a",
      capability_payload: { "supports_process_runs" => true }
    )

    duplicate = ExecutionRuntime.new(
      installation: installation,
      kind: "local",
      display_name: "Duplicate Runtime",
      runtime_fingerprint: "runtime-a",
      connection_metadata: {},
      capability_payload: {}
    )
    invalid_payload = ExecutionRuntime.new(
      installation: installation,
      kind: "local",
      display_name: "Invalid Payload",
      runtime_fingerprint: "runtime-b",
      connection_metadata: {},
      capability_payload: []
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:runtime_fingerprint], "has already been taken"
    assert_not invalid_payload.valid?
    assert_includes invalid_payload.errors[:capability_payload], "must be a Hash"
  end
end
