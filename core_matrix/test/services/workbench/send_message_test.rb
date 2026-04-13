require "test_helper"

class Workbench::SendMessageTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "appends a new user turn to an existing conversation as pending bootstrap work" do
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])

    result = nil

    assert_no_difference(["UserAgentBinding.count", "Workspace.count", "Conversation.count"]) do
      assert_enqueued_with(job: Turns::MaterializeAndDispatchJob) do
        assert_difference(["Turn.count", "Message.count"], +1) do
          assert_no_difference("WorkflowRun.count") do
          result = Workbench::SendMessage.call(
            conversation: conversation,
            content: "Follow up"
          )
          end
        end
      end
    end

    assert_equal conversation, result.conversation
    assert_equal "Follow up", result.message.content
    assert_equal result.turn, result.message.turn
    assert_equal "pending", result.turn.workflow_bootstrap_state
    assert_equal result.turn, conversation.reload.latest_turn
    assert_equal result.turn, conversation.latest_active_turn
    assert_nil conversation.latest_active_workflow_run
    assert_equal result.message, conversation.latest_message
    assert_equal result.message.created_at.to_i, conversation.last_activity_at.to_i
    refute_respond_to result, :workflow_run
  end

  test "keeps using the runtime pinned by the conversation current execution state" do
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    override_runtime = create_execution_runtime!(installation: context[:installation])
    create_execution_runtime_connection!(
      installation: context[:installation],
      execution_runtime: override_runtime
    )
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace], agent: context[:agent])
    initialize_current_execution_epoch!(conversation)
    ConversationExecutionEpochs::RetargetCurrent.call(
      conversation: conversation,
      execution_runtime: override_runtime
    )

    result = nil

    assert_enqueued_with(job: Turns::MaterializeAndDispatchJob) do
      assert_difference(["Turn.count", "Message.count"], +1) do
        assert_no_difference("WorkflowRun.count") do
        result = Workbench::SendMessage.call(
          conversation: conversation,
          content: "Follow up",
          selector: "candidate:codex_subscription/gpt-5.3-codex"
        )
        end
      end
    end

    assert_equal override_runtime, result.turn.execution_runtime
    assert_equal "pending", result.turn.workflow_bootstrap_state
  end

  test "sends a message within seventy-five SQL queries" do
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])

    assert_sql_query_count_at_most(75) do
      result = Workbench::SendMessage.call(
        conversation: conversation,
        content: "Follow up"
      )

      assert_equal "Follow up", result.message.content
    end
  end
end
