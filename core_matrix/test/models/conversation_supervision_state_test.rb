require "test_helper"

class ConversationSupervisionStateTest < ActiveSupport::TestCase
  test "stores one durable supervision state per conversation with public id boundaries" do
    context = create_workspace_context!
    conversation = create_conversation_record!(
      workspace: context[:workspace],
      installation: context[:installation],
      execution_runtime: context[:execution_runtime],
      agent_program: context[:agent_program]
    )

    state = ConversationSupervisionState.create!(
      installation: context[:installation],
      target_conversation: conversation,
      overall_state: "running",
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
      agent_program: context[:agent_program]
    )
    ConversationSupervisionState.create!(
      installation: context[:installation],
      target_conversation: conversation,
      overall_state: "running",
      last_progress_at: Time.current,
      status_payload: {}
    )

    duplicate = ConversationSupervisionState.new(
      installation: context[:installation],
      target_conversation: conversation,
      overall_state: "waiting",
      waiting_summary: "Waiting on review",
      last_progress_at: Time.current,
      status_payload: {}
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:target_conversation], "has already been taken"

    other_installation = create_raw_installation!
    mismatched = ConversationSupervisionState.new(
      installation: other_installation,
      target_conversation: conversation,
      overall_state: "running",
      last_progress_at: Time.current,
      status_payload: {}
    )

    assert_not mismatched.valid?
    assert_includes mismatched.errors[:target_conversation], "must belong to the same installation"
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
