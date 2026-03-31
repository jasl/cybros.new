require "test_helper"

class ExecutionEnvironmentTest < ActiveSupport::TestCase
  test "generates and resolves a public id" do
    execution_environment = create_execution_environment!

    assert execution_environment.public_id.present?
    assert_equal execution_environment, ExecutionEnvironment.find_by_public_id!(execution_environment.public_id)
  end

  test "tracks kind and connection metadata" do
    installation = create_installation!
    environment = create_execution_environment!(
      installation: installation,
      kind: "container",
      connection_metadata: {
        "transport" => "http",
        "base_url" => "https://agents.example.test",
      }
    )

    assert environment.container?
    assert_equal "https://agents.example.test", environment.connection_metadata["base_url"]

    invalid_environment = ExecutionEnvironment.new(
      installation: installation,
      kind: "local",
      connection_metadata: []
    )

    assert_not invalid_environment.valid?
    assert_includes invalid_environment.errors[:connection_metadata], "must be a Hash"
  end

  test "requires an installation-local environment fingerprint and capability payload hash" do
    installation = create_installation!
    create_execution_environment!(
      installation: installation,
      environment_fingerprint: "host-a",
      capability_payload: { "conversation_attachment_upload" => true }
    )

    duplicate = ExecutionEnvironment.new(
      installation: installation,
      kind: "local",
      environment_fingerprint: "host-a",
      connection_metadata: {},
      capability_payload: {}
    )
    invalid_payload = ExecutionEnvironment.new(
      installation: installation,
      kind: "local",
      environment_fingerprint: "host-b",
      connection_metadata: {},
      capability_payload: []
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:environment_fingerprint], "has already been taken"
    assert_not invalid_payload.valid?
    assert_includes invalid_payload.errors[:capability_payload], "must be a Hash"
  end

  test "renders its runtime plane through the shared runtime capability contract" do
    environment = create_execution_environment!(
      capability_payload: { "conversation_attachment_upload" => false },
      tool_catalog: [
        {
          "tool_name" => "exec_command",
          "tool_kind" => "environment_runtime",
          "implementation_source" => "execution_environment",
          "implementation_ref" => "env/exec_command",
          "input_schema" => { "type" => "object", "properties" => {} },
          "result_schema" => { "type" => "object", "properties" => {} },
          "streaming_support" => false,
          "idempotency_policy" => "best_effort",
        },
      ]
    )
    contract = RuntimeCapabilityContract.build(execution_environment: environment)

    assert_equal environment.capability_payload, contract.environment_plane.fetch("capability_payload")
    assert_equal(
      [
        {
          "tool_name" => "exec_command",
          "tool_kind" => "environment_runtime",
          "implementation_source" => "execution_environment",
          "implementation_ref" => "env/exec_command",
          "input_schema" => { "type" => "object", "properties" => {} },
          "result_schema" => { "type" => "object", "properties" => {} },
          "streaming_support" => false,
          "idempotency_policy" => "best_effort",
          "execution_policy" => { "parallel_safe" => false },
        },
      ],
      contract.environment_plane.fetch("tool_catalog")
    )
  end
end
