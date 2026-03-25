require "test_helper"

class Turns::QueueFollowUpTest < ActiveSupport::TestCase
  test "creates a queued follow up turn with a new selected input message" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    Turns::StartUserTurn.call(
      conversation: conversation,
      content: "First input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    queued = Turns::QueueFollowUp.call(
      conversation: conversation,
      content: "Follow up input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    assert queued.queued?
    assert queued.manual_user?
    assert_equal 2, queued.sequence
    assert_equal "User", queued.source_ref_type
    assert_equal context[:user].public_id, queued.source_ref_id
    assert_instance_of UserMessage, queued.selected_input_message
    assert_equal "Follow up input", queued.selected_input_message.content
  end

  test "rejects queueing when no active work exists" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])

    assert_raises(ActiveRecord::RecordInvalid) do
      Turns::QueueFollowUp.call(
        conversation: conversation,
        content: "Should not queue",
        agent_deployment: context[:agent_deployment],
        resolved_config_snapshot: {},
        resolved_model_selection_snapshot: {}
      )
    end
  end
end
