require "test_helper"

class ConversationSupervisionStateTest < ActiveSupport::TestCase
  test "stores one durable supervision state per conversation with public id boundaries" do
    context = create_workspace_context!
    conversation = create_conversation_record!(
      workspace: context[:workspace],
      installation: context[:installation],
      execution_runtime: context[:execution_runtime],
      agent: context[:agent]
    )

    state = ConversationSupervisionState.create!(
      installation: context[:installation],
      target_conversation: conversation,
      user: conversation.user,
      workspace: conversation.workspace,
      agent: conversation.agent,
      overall_state: "idle",
      board_lane: "idle",
      lane_changed_at: Time.current,
      retry_due_at: 5.minutes.from_now,
      active_plan_item_count: 1,
      completed_plan_item_count: 1,
      active_subagent_count: 2,
      board_badges: ["2 child tasks"],
      last_terminal_state: "completed",
      last_terminal_at: 1.minute.ago,
      current_owner_kind: "agent_task_run",
      current_owner_public_id: "task_run_public_id",
      request_summary: "Replace the observation schema",
      current_focus_summary: "Adding the canonical supervision aggregates",
      recent_progress_summary: "Finished reviewing the old models",
      waiting_summary: nil,
      blocked_summary: nil,
      next_step_hint: "Rewrite the migrations",
      last_progress_at: Time.current,
      status_payload: { "current_owner_public_id" => "task_run_public_id" }
    )

    assert state.public_id.present?
    assert_equal state, ConversationSupervisionState.find_by_public_id!(state.public_id)
    assert_equal conversation, state.target_conversation
    assert_equal "task_run_public_id", state.current_owner_public_id
    assert_equal "idle", state.board_lane
    assert_equal "completed", state.last_terminal_state
    assert state.last_terminal_at.present?
    assert_equal 1, state.active_plan_item_count
    assert_equal 1, state.completed_plan_item_count
    assert_equal 2, state.active_subagent_count
    assert_equal ["2 child tasks"], state.board_badges
    assert_equal({ "current_owner_public_id" => "task_run_public_id" }, state.status_payload)
    assert_equal state, conversation.conversation_supervision_state
    assert_not_nil Conversation.reflect_on_association(:conversation_supervision_state)
  end

  test "requires one state per conversation and a matching installation" do
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
      last_progress_at: Time.current,
      status_payload: {}
    )

    duplicate = ConversationSupervisionState.new(
      installation: context[:installation],
      target_conversation: conversation,
      user: conversation.user,
      workspace: conversation.workspace,
      agent: conversation.agent,
      overall_state: "idle",
      board_lane: "idle",
      waiting_summary: "Waiting on review",
      last_progress_at: Time.current,
      board_badges: [],
      status_payload: {}
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:target_conversation], "has already been taken"

    other_installation = create_raw_installation!
    mismatched = ConversationSupervisionState.new(
      installation: other_installation,
      target_conversation: conversation,
      user: conversation.user,
      workspace: conversation.workspace,
      agent: conversation.agent,
      overall_state: "idle",
      board_lane: "idle",
      last_progress_at: Time.current,
      board_badges: [],
      status_payload: {}
    )

    assert_not mismatched.valid?
    assert_includes mismatched.errors[:target_conversation], "must belong to the same installation"
  end

  test "requires duplicated owner context to match the target conversation" do
    context = create_workspace_context!
    conversation = create_conversation_record!(
      workspace: context[:workspace],
      installation: context[:installation],
      execution_runtime: context[:execution_runtime],
      agent: context[:agent]
    )
    foreign = create_workspace_context!

    state = ConversationSupervisionState.new(
      installation: context[:installation],
      target_conversation: conversation,
      user_id: foreign[:user].id,
      workspace_id: foreign[:workspace].id,
      agent_id: foreign[:agent].id,
      overall_state: "idle",
      board_lane: "idle",
      last_progress_at: Time.current,
      board_badges: [],
      status_payload: {}
    )

    assert_not state.valid?
    assert_includes state.errors[:user], "must match the target conversation user"
    assert_includes state.errors[:workspace], "must match the target conversation workspace"
    assert_includes state.errors[:agent], "must match the target conversation agent"
  end

  test "stores cold machine status in a detail row instead of the header table" do
    context = create_workspace_context!
    conversation = create_conversation_record!(
      workspace: context[:workspace],
      installation: context[:installation],
      execution_runtime: context[:execution_runtime],
      agent: context[:agent]
    )

    state = ConversationSupervisionState.create!(
      installation: context[:installation],
      target_conversation: conversation,
      user: conversation.user,
      workspace: conversation.workspace,
      agent: conversation.agent,
      overall_state: "running",
      board_lane: "active",
      last_progress_at: Time.current,
      board_badges: [],
      status_payload: { "runtime_evidence" => { "active_command" => { "command_run_public_id" => "cmd-1" } } }
    )

    refute_includes ConversationSupervisionState.column_names, "status_payload"
    assert_equal :has_one, ConversationSupervisionState.reflect_on_association(:conversation_supervision_state_detail)&.macro
    assert_equal "cmd-1", state.status_payload.dig("runtime_evidence", "active_command", "command_run_public_id")
    assert_equal "cmd-1", state.conversation_supervision_state_detail.status_payload.dig("runtime_evidence", "active_command", "command_run_public_id")
  end

  private

  def create_raw_installation!
    now = Time.current
    sql = <<~SQL.squish
      INSERT INTO installations (name, bootstrap_state, global_settings, created_at, updated_at)
      VALUES (#{ApplicationRecord.connection.quote("Supervision State Installation #{next_test_sequence}")},
              'bootstrapped',
              '{}',
              #{ApplicationRecord.connection.quote(now)},
              #{ApplicationRecord.connection.quote(now)})
      RETURNING id
    SQL
    installation_id = ApplicationRecord.connection.select_value(sql)
    Installation.find(installation_id)
  end
end
