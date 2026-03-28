require "test_helper"

class RuntimeCapabilities::ComposeForConversationTest < ActiveSupport::TestCase
  test "conversation attachments stay disabled when the environment does not allow uploads" do
    installation = create_installation!
    environment = create_execution_environment!(
      installation: installation,
      capability_payload: { "conversation_attachment_upload" => false }
    )
    agent_installation = create_agent_installation!(installation: installation)
    deployment = create_agent_deployment!(
      installation: installation,
      agent_installation: agent_installation,
      execution_environment: environment
    )
    create_capability_snapshot!(
      agent_deployment: deployment,
      tool_catalog: default_tool_catalog("shell_exec", "file_upload")
    ).tap do |snapshot|
      deployment.update!(active_capability_snapshot: snapshot)
    end

    contract = RuntimeCapabilities::ComposeForConversation.call(
      execution_environment: environment,
      agent_deployment: deployment
    )
    expected_contract = RuntimeCapabilityContract.build(
      execution_environment: environment,
      capability_snapshot: deployment.active_capability_snapshot
    )

    assert_equal false, contract.fetch("conversation_attachment_upload")
    assert_equal expected_contract.conversation_payload(
      execution_environment_id: environment.public_id,
      agent_deployment_id: deployment.public_id
    ), contract
  end

  test "conversation attachments stay enabled when the environment allows uploads" do
    installation = create_installation!
    environment = create_execution_environment!(
      installation: installation,
      capability_payload: { "conversation_attachment_upload" => true }
    )
    agent_installation = create_agent_installation!(installation: installation)
    deployment = create_agent_deployment!(
      installation: installation,
      agent_installation: agent_installation,
      execution_environment: environment
    )

    contract = RuntimeCapabilities::ComposeForConversation.call(
      execution_environment: environment,
      agent_deployment: deployment
    )
    expected_contract = RuntimeCapabilityContract.build(
      execution_environment: environment,
      capability_snapshot: deployment.active_capability_snapshot
    )

    assert_equal true, contract.fetch("conversation_attachment_upload")
    assert_equal expected_contract.conversation_payload(
      execution_environment_id: environment.public_id,
      agent_deployment_id: deployment.public_id
    ), contract
  end

  test "conversation tool catalog prefers environment tools over agent tools with the same name" do
    installation = create_installation!
    environment = create_execution_environment!(
      installation: installation,
      tool_catalog: [
        {
          "tool_name" => "shell_exec",
          "tool_kind" => "environment_runtime",
          "implementation_source" => "execution_environment",
          "implementation_ref" => "env/shell_exec",
          "input_schema" => { "type" => "object", "properties" => {} },
          "result_schema" => { "type" => "object", "properties" => {} },
          "streaming_support" => false,
          "idempotency_policy" => "best_effort",
        },
      ]
    )
    agent_installation = create_agent_installation!(installation: installation)
    deployment = create_agent_deployment!(
      installation: installation,
      agent_installation: agent_installation,
      execution_environment: environment
    )
    create_capability_snapshot!(
      agent_deployment: deployment,
      tool_catalog: [
        {
          "tool_name" => "shell_exec",
          "tool_kind" => "agent_observation",
          "implementation_source" => "agent",
          "implementation_ref" => "agent/shell_exec",
          "input_schema" => { "type" => "object", "properties" => {} },
          "result_schema" => { "type" => "object", "properties" => {} },
          "streaming_support" => false,
          "idempotency_policy" => "best_effort",
        },
      ]
    ).tap do |snapshot|
      deployment.update!(active_capability_snapshot: snapshot)
    end

    contract = RuntimeCapabilities::ComposeForConversation.call(
      execution_environment: environment,
      agent_deployment: deployment
    )
    expected_contract = RuntimeCapabilityContract.build(
      execution_environment: environment,
      capability_snapshot: deployment.active_capability_snapshot
    )

    shell_entry = contract.fetch("tool_catalog").find { |entry| entry.fetch("tool_name") == "shell_exec" }

    assert_equal "environment_runtime", shell_entry.fetch("tool_kind")
    assert_equal expected_contract.conversation_payload(
      execution_environment_id: environment.public_id,
      agent_deployment_id: deployment.public_id
    ), contract
  end
end
