require "test_helper"

class ConversationSupervision::PublishUpdateTest < ActiveSupport::TestCase
  test "publishes material supervision changes and ignores cosmetic rewrites" do
    state = create_supervision_state!(board_lane: "active", current_focus_summary: "Project runtime state")
    latest_feed_entry = ConversationSupervisionFeedEntry.create!(
      installation: state.installation,
      target_conversation: state.target_conversation,
      target_turn: state.target_conversation.turns.first,
      sequence: 1,
      event_kind: "progress_recorded",
      summary: "Reviewed the supervision board.",
      details_payload: {},
      occurred_at: Time.current
    )
    events = []
    callback = lambda do |_name, _started, _finished, _id, payload|
      events << payload
    end

    ActiveSupport::Notifications.subscribed(callback, "conversation_supervision.updated") do
      ConversationSupervision::PublishUpdate.call(
        conversation_supervision_state: state,
        latest_feed_entry: latest_feed_entry,
        previous_attributes: {
          "board_lane" => "queued",
          "current_focus_summary" => "Queue the work",
          "recent_progress_summary" => state.recent_progress_summary,
          "active_plan_item_count" => state.active_plan_item_count,
          "completed_plan_item_count" => state.completed_plan_item_count,
          "active_subagent_count" => state.active_subagent_count,
          "board_badges" => state.board_badges,
          "retry_due_at" => state.retry_due_at,
          "overall_state" => state.overall_state,
          "last_terminal_state" => state.last_terminal_state,
          "last_terminal_at" => state.last_terminal_at,
          "current_owner_kind" => state.current_owner_kind,
          "current_owner_public_id" => state.current_owner_public_id
        }
      )
      ConversationSupervision::PublishUpdate.call(
        conversation_supervision_state: state,
        latest_feed_entry: latest_feed_entry,
        previous_attributes: {
          "board_lane" => state.board_lane,
          "current_focus_summary" => state.current_focus_summary,
          "recent_progress_summary" => state.recent_progress_summary,
          "active_plan_item_count" => state.active_plan_item_count,
          "completed_plan_item_count" => state.completed_plan_item_count,
          "active_subagent_count" => state.active_subagent_count,
          "board_badges" => state.board_badges,
          "retry_due_at" => state.retry_due_at,
          "overall_state" => state.overall_state,
          "last_terminal_state" => state.last_terminal_state,
          "last_terminal_at" => state.last_terminal_at,
          "current_owner_kind" => state.current_owner_kind,
          "current_owner_public_id" => state.current_owner_public_id
        }
      )
    end

    assert_equal 1, events.size
    assert_equal state.public_id, events.first.fetch("conversation_supervision_state_id")
    assert_equal "active", events.first.fetch("board_lane")
    assert_equal "completed", events.first.fetch("last_terminal_state")
    assert_equal "progress_recorded", events.first.fetch("latest_feed_entry").fetch("event_kind")
  end

  private

  def create_supervision_state!(board_lane:, current_focus_summary:)
    context = create_workspace_context!
    conversation = create_conversation_record!(
      workspace: context[:workspace],
      installation: context[:installation],
      execution_runtime: context[:execution_runtime],
      agent_program: context[:agent_program]
    )
    Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Summarize the recent work",
      execution_runtime: context[:execution_runtime],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    ConversationSupervisionState.create!(
      installation: context[:installation],
      target_conversation: conversation,
      overall_state: "running",
      board_lane: board_lane,
      lane_changed_at: Time.current,
      active_plan_item_count: 1,
      completed_plan_item_count: 0,
      active_subagent_count: 0,
      board_badges: [],
      last_terminal_state: "completed",
      last_terminal_at: 1.minute.ago,
      current_owner_kind: "agent_task_run",
      current_owner_public_id: "task-run-1",
      request_summary: "Replace the observation schema",
      current_focus_summary: current_focus_summary,
      recent_progress_summary: "Rebuilt the conversation projector",
      next_step_hint: "Publish the new update signal",
      last_progress_at: Time.current,
      status_payload: {}
    )
  end
end
