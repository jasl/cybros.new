require "test_helper"

class AgentTaskProgressEntryTest < ActiveSupport::TestCase
  test "stores append-only semantic progress entries and rejects internal token summaries" do
    context = build_agent_control_context!
    agent_task_run = create_agent_task_run!(
      workflow_node: context[:workflow_node],
      lifecycle_state: "running",
      started_at: Time.current,
      supervision_state: "running",
      focus_kind: "implementation",
      last_progress_at: Time.current,
      supervision_payload: {}
    )

    entry = AgentTaskProgressEntry.create!(
      installation: context[:installation],
      agent_task_run: agent_task_run,
      sequence: 1,
      entry_kind: "progress_recorded",
      summary: "Projected the new supervision fields onto the task",
      details_payload: {},
      occurred_at: Time.current
    )

    assert entry.public_id.present?
    assert_equal entry, AgentTaskProgressEntry.find_by_public_id!(entry.public_id)

    invalid_entry = AgentTaskProgressEntry.new(
      installation: context[:installation],
      agent_task_run: agent_task_run,
      sequence: 2,
      entry_kind: "progress_recorded",
      summary: "provider_round_3_tool_1",
      details_payload: {},
      occurred_at: Time.current
    )

    assert_not invalid_entry.valid?
    assert_includes invalid_entry.errors[:summary], "must not expose internal runtime tokens"
  end

  test "allows semantic summaries and requires linked subagents to belong to the task conversation" do
    context = build_agent_control_context!
    agent_task_run = create_agent_task_run!(
      workflow_node: context[:workflow_node],
      lifecycle_state: "running",
      started_at: Time.current,
      supervision_state: "running",
      focus_kind: "implementation",
      last_progress_at: Time.current,
      supervision_payload: {}
    )
    unrelated_owner = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_program_version: context[:agent_program_version]
    )
    unrelated_child = create_conversation_record!(
      workspace: context[:workspace],
      installation: context[:installation],
      parent_conversation: unrelated_owner,
      execution_runtime: context[:execution_runtime],
      agent_program_version: context[:agent_program_version],
      kind: "fork",
      addressability: "agent_addressable"
    )
    unrelated_session = SubagentSession.create!(
      installation: context[:installation],
      owner_conversation: unrelated_owner,
      conversation: unrelated_child,
      scope: "conversation",
      profile_key: "worker",
      depth: 0
    )

    semantic_entry = AgentTaskProgressEntry.new(
      installation: context[:installation],
      agent_task_run: agent_task_run,
      sequence: 2,
      entry_kind: "progress_recorded",
      summary: "Retried tool_invocation cleanup after partial output",
      details_payload: {},
      occurred_at: Time.current
    )

    assert semantic_entry.valid?, semantic_entry.errors.full_messages.to_sentence

    invalid_link = AgentTaskProgressEntry.new(
      installation: context[:installation],
      agent_task_run: agent_task_run,
      subagent_session: unrelated_session,
      sequence: 3,
      entry_kind: "progress_recorded",
      summary: "Delegated follow-up verification to a child worker",
      details_payload: {},
      occurred_at: Time.current
    )

    assert_not invalid_link.valid?
    assert_includes invalid_link.errors[:subagent_session], "must be owned by the task conversation"
  end
end
