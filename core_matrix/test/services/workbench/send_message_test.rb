require "test_helper"

class Workbench::SendMessageTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "appends a new user turn to an existing conversation without creating a workspace or conversation" do
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])

    result = nil

    assert_no_difference(["UserAgentBinding.count", "Workspace.count", "Conversation.count"]) do
      assert_enqueued_with(job: Workflows::ExecuteNodeJob) do
        assert_difference(["Turn.count", "Message.count", "WorkflowRun.count"], +1) do
          result = Workbench::SendMessage.call(
            conversation: conversation,
            content: "Follow up"
          )
        end
      end
    end

    assert_equal conversation, result.conversation
    assert_equal "Follow up", result.message.content
    assert_equal result.turn, result.message.turn
    assert_equal result.turn, result.workflow_run.turn
  end
end
