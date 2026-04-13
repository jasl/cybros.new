require "test_helper"

class ConversationSupervision::ListBoardCardsTest < ActiveSupport::TestCase
  test "lists board cards in deterministic lane and activity order with filtering" do
    context = create_workspace_context!
    active_newest = create_state_for_list!(context:, board_lane: "active", minutes_ago: 1)
    create_state_for_list!(context:, board_lane: "active", minutes_ago: 5)
    blocked = create_state_for_list!(context:, board_lane: "blocked", minutes_ago: 2)

    cards = ConversationSupervision::ListBoardCards.call(installation: context[:installation])
    blocked_cards = ConversationSupervision::ListBoardCards.call(
      installation: context[:installation],
      board_lane: "blocked"
    )

    assert_equal [active_newest.target_conversation.public_id, blocked.target_conversation.public_id],
      [cards.first.fetch("conversation_id"), cards.last.fetch("conversation_id")]
    assert_equal [blocked.target_conversation.public_id],
      blocked_cards.map { |card| card.fetch("conversation_id") }
  end

  test "lists board cards without loading cold status detail rows" do
    context = create_workspace_context!
    create_state_for_list!(context:, board_lane: "active", minutes_ago: 1)

    queries = capture_sql_queries do
      ConversationSupervision::ListBoardCards.call(installation: context[:installation])
    end

    assert queries.none? { |sql| sql.include?("conversation_supervision_state_details") },
      "Expected board list reads to stay on header rows, got:\n#{queries.join("\n")}"
  end

  private

  def create_state_for_list!(context:, board_lane:, minutes_ago:)
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
      overall_state: board_lane == "blocked" ? "blocked" : "running",
      board_lane: board_lane,
      lane_changed_at: minutes_ago.minutes.ago,
      active_plan_item_count: 1,
      completed_plan_item_count: 0,
      active_subagent_count: 0,
      board_badges: [],
      current_owner_kind: "agent_task_run",
      current_owner_public_id: "task-run-#{next_test_sequence}",
      request_summary: "Replace the observation schema",
      current_focus_summary: "Project runtime state into supervision",
      recent_progress_summary: "Rebuilt the conversation projector",
      next_step_hint: "Publish the new update signal",
      last_progress_at: minutes_ago.minutes.ago,
      status_payload: {}
    )
  end
end
