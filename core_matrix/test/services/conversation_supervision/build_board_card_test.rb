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

  test "builds a board card without loading the cold status detail row" do
    state = create_supervision_state!(
      board_lane: "active",
      active_plan_item_count: 2,
      completed_plan_item_count: 1,
      active_subagent_count: 1,
      board_badges: ["1 child task"],
      last_terminal_state: "completed"
    )

    queries = capture_sql_queries do
      ConversationSupervision::BuildBoardCard.call(conversation_supervision_state: state.reload)
    end

    assert queries.none? { |sql| sql.include?("conversation_supervision_state_details") },
      "Expected board card reads to stay on header rows, got:\n#{queries.join("\n")}"
  end

  test "builds a queued turn-owned board card from pending bootstrap state" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      agent: context[:agent]
    )
    turn = Turns::AcceptPendingUserTurn.call(
      conversation: conversation,
      content: "Build a complete browser-playable React 2048 game and add automated tests.",
      selector_source: "app_api",
      selector: "candidate:codex_subscription/gpt-5.3-codex"
    )
    state = Conversations::ProjectTurnBootstrapState.call(turn: turn)

    card = ConversationSupervision::BuildBoardCard.call(
      conversation_supervision_state: state
    )

    assert_equal "queued", card.fetch("board_lane")
    assert_equal "queued", card.fetch("overall_state")
    assert_equal "turn", card.fetch("current_owner_kind")
    assert_equal turn.public_id, card.fetch("current_owner_public_id")
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
