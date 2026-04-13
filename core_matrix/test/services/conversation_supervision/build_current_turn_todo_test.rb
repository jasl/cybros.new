require "test_helper"

class ConversationSupervision::BuildCurrentTurnTodoTest < ActiveSupport::TestCase
  include ConversationSupervisionFixtureBuilder

  test "returns the persisted turn todo plan when the active task has one" do
    fixture = prepare_conversation_supervision_context_with_turn_todo_plan!
    fixture.fetch(:conversation).conversation_supervision_state.update!(
      current_owner_kind: "agent_task_run",
      current_owner_public_id: fixture.fetch(:agent_task_run).public_id
    )

    projection = ConversationSupervision::BuildCurrentTurnTodo.call(
      conversation: fixture.fetch(:conversation)
    )

    assert_equal "render-snapshot", projection.dig("plan_summary", "current_item_key")
    assert_equal "Rendering the frozen supervision snapshot",
      projection.dig("plan_view", "current_item", "title")
    assert_equal [], projection.fetch("synthetic_turn_feed")
  end

  test "returns the persisted turn todo plan when supervision state points at the agent task run" do
    fixture = prepare_conversation_supervision_context_with_turn_todo_plan!
    conversation = fixture.fetch(:conversation)
    task_run = fixture.fetch(:agent_task_run)

    conversation.conversation_supervision_state.update!(
      current_owner_kind: "agent_task_run",
      current_owner_public_id: task_run.public_id
    )

    projection = ConversationSupervision::BuildCurrentTurnTodo.call(
      conversation: conversation
    )

    assert_equal "render-snapshot", projection.dig("plan_summary", "current_item_key")
    assert_equal "Rendering the frozen supervision snapshot",
      projection.dig("plan_view", "current_item", "title")
  end

  test "returns an empty projection when supervision state is missing" do
    fixture = prepare_conversation_supervision_context_with_turn_todo_plan!
    fixture.fetch(:conversation).conversation_supervision_state.destroy!

    projection = ConversationSupervision::BuildCurrentTurnTodo.call(
      conversation: fixture.fetch(:conversation)
    )

    assert_nil projection["plan_view"]
    assert_nil projection["plan_summary"]
    assert_equal [], projection.fetch("synthetic_turn_feed")
  end

  test "returns an empty projection when supervision state points at a non-task owner" do
    fixture = prepare_conversation_supervision_context_with_turn_todo_plan!
    fixture.fetch(:conversation).conversation_supervision_state.update!(
      current_owner_kind: "turn",
      current_owner_public_id: fixture.fetch(:turn).public_id
    )

    projection = ConversationSupervision::BuildCurrentTurnTodo.call(
      conversation: fixture.fetch(:conversation)
    )

    assert_nil projection["plan_view"]
    assert_nil projection["plan_summary"]
    assert_equal [], projection.fetch("synthetic_turn_feed")
  end

  test "still uses an explicitly supplied active task run for internal callers" do
    fixture = prepare_conversation_supervision_context_with_turn_todo_plan!
    conversation = fixture.fetch(:conversation)
    task_run = fixture.fetch(:agent_task_run)
    conversation.conversation_supervision_state.destroy!

    projection = ConversationSupervision::BuildCurrentTurnTodo.call(
      conversation: conversation,
      active_agent_task_run: task_run
    )

    assert_equal "render-snapshot", projection.dig("plan_summary", "current_item_key")
    assert_equal "Rendering the frozen supervision snapshot",
      projection.dig("plan_view", "current_item", "title")
  end

  test "returns no semantic fallback plan for provider-backed work without a persisted plan" do
    fixture = prepare_provider_backed_conversation_supervision_context!

    projection = ConversationSupervision::BuildCurrentTurnTodo.call(
      conversation: fixture.fetch(:conversation)
    )

    assert_nil projection["plan_view"]
    assert_nil projection["plan_summary"]
    assert_equal [], projection.fetch("synthetic_turn_feed")
  end

  test "does not leak workflow tool names into the fallback projection" do
    fixture = prepare_provider_backed_conversation_supervision_context!

    projection = ConversationSupervision::BuildCurrentTurnTodo.call(
      conversation: fixture.fetch(:conversation)
    )

    refute_match(/provider round|command_run_wait|exec_command|workspace_tree/i, projection.to_json)
  end
end
