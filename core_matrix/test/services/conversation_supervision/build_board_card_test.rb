require "test_helper"

class ConversationSupervision::BuildBoardCardTest < ActiveSupport::TestCase
  test "builds a structured board card from conversation supervision state" do
    state = create_supervision_state!(
      board_lane: "active",
      active_plan_item_count: 2,
      completed_plan_item_count: 1,
      active_subagent_count: 1,
      board_badges: ["1 child task"],
      last_terminal_state: "completed"
    )

    card = ConversationSupervision::BuildBoardCard.call(
      conversation_supervision_state: state
    )

    assert_equal state.target_conversation.public_id, card.fetch("conversation_id")
    assert_equal state.public_id, card.fetch("conversation_supervision_state_id")
    assert_equal "active", card.fetch("board_lane")
    assert_equal "running", card.fetch("overall_state")
    assert_equal 2, card.fetch("active_plan_item_count")
    assert_equal 1, card.fetch("completed_plan_item_count")
    assert_equal 1, card.fetch("active_subagent_count")
    assert_equal ["1 child task"], card.fetch("board_badges")
    assert_equal "completed", card.fetch("last_terminal_state")
  end

  private

  def create_supervision_state!(board_lane:, active_plan_item_count:, completed_plan_item_count:, active_subagent_count:, board_badges:, last_terminal_state:)
    context = create_workspace_context!
    conversation = create_conversation_record!(
      workspace: context[:workspace],
      installation: context[:installation],
      execution_runtime: context[:execution_runtime],
      agent: context[:agent]
    )

    ConversationSupervisionState.create!(
      installation: context[:installation],
      target_conversation: conversation,
      user: conversation.user,
      workspace: conversation.workspace,
      agent: conversation.agent,
      overall_state: "running",
      board_lane: board_lane,
      lane_changed_at: Time.current,
      active_plan_item_count: active_plan_item_count,
      completed_plan_item_count: completed_plan_item_count,
      active_subagent_count: active_subagent_count,
      board_badges: board_badges,
      last_terminal_state: last_terminal_state,
      last_terminal_at: 1.minute.ago,
      current_owner_kind: "agent_task_run",
      current_owner_public_id: "task-run-1",
      request_summary: "Replace the observation schema",
      current_focus_summary: "Project runtime state into supervision",
      recent_progress_summary: "Rebuilt the conversation projector",
      next_step_hint: "Publish the new update signal",
      last_progress_at: Time.current,
      status_payload: {}
    )
  end
end
