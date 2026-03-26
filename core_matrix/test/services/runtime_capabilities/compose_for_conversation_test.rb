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

    assert_equal false, contract.fetch("conversation_attachment_upload")
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

    assert_equal true, contract.fetch("conversation_attachment_upload")
  end
end
