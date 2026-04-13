require "test_helper"

class Workbench::SendMessageWeightTest < ActiveSupport::TestCase
  test "sends a message as pending bootstrap work within forty SQL queries" do
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])

    assert_sql_query_count_at_most(40) do
      result = Workbench::SendMessage.call(
        conversation: conversation,
        content: "Follow up"
      )

      assert_equal "pending", result.turn.workflow_bootstrap_state
    end
  end
end
