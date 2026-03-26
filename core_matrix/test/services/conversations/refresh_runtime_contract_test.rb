require "test_helper"

class Conversations::RefreshRuntimeContractTest < ActiveSupport::TestCase
  test "refresh reflects environment capability changes without deployment rotation" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )

    context[:execution_environment].update!(
      capability_payload: { "conversation_attachment_upload" => false }
    )

    contract = Conversations::RefreshRuntimeContract.call(conversation: conversation.reload)

    assert_equal false, contract.fetch("conversation_attachment_upload")
  end
end
