require "test_helper"

class Conversations::SwitchAgentDeploymentTest < ActiveSupport::TestCase
  test "switches the active deployment within the bound execution environment" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    replacement = create_agent_deployment!(
      installation: context[:installation],
      agent_installation: context[:agent_installation],
      execution_environment: context[:execution_environment],
      fingerprint: "replacement-#{next_test_sequence}",
      bootstrap_state: "pending"
    )

    result = Conversations::SwitchAgentDeployment.call(
      conversation: conversation,
      agent_deployment: replacement
    )

    assert_equal replacement, result.conversation.reload.agent_deployment
    assert_equal replacement.public_id, result.runtime_contract.fetch("agent_deployment_id")
  end

  test "rejects switching to a deployment from another execution environment" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    other_environment = create_execution_environment!(installation: context[:installation])
    replacement = create_agent_deployment!(
      installation: context[:installation],
      agent_installation: context[:agent_installation],
      execution_environment: other_environment,
      fingerprint: "replacement-#{next_test_sequence}",
      bootstrap_state: "pending"
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::SwitchAgentDeployment.call(
        conversation: conversation,
        agent_deployment: replacement
      )
    end

    assert_includes error.record.errors[:agent_deployment], "must belong to the bound execution environment"
  end
end
