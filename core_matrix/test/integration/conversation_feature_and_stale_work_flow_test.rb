require "test_helper"

class ConversationFeatureAndStaleWorkFlowTest < ActiveSupport::TestCase
  test "newly queued follow up turns pick the latest conversation policy while the active turn keeps its frozen snapshot" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      executor_program: context[:executor_program],
      agent_program_version: context[:agent_program_version]
    )
    conversation.update!(during_generation_input_policy: "queue")

    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Original input",
      agent_program_version: context[:agent_program_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    create_workflow_run!(turn: turn)
    attach_selected_output!(turn, content: "Existing output")

    conversation.update!(
      enabled_feature_ids: Conversation::FEATURE_IDS - ["conversation_branching"],
      during_generation_input_policy: "restart"
    )

    queued_turn = Turns::SteerCurrentInput.call(
      turn: turn,
      content: "Follow up input"
    )

    assert_equal "queue", turn.reload.feature_policy_snapshot.fetch("during_generation_input_policy")
    assert_equal "restart", queued_turn.feature_policy_snapshot.fetch("during_generation_input_policy")

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::CreateBranch.call(
        parent: conversation,
        historical_anchor_message_id: turn.selected_input_message_id
      )
    end

    detail = error.record.errors.details.fetch(:base).find { |candidate| candidate[:error] == :feature_not_enabled }
    assert_equal "conversation_branching", detail.fetch(:feature_id)
  end
end
