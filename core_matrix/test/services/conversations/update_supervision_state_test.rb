require "test_helper"

class Conversations::UpdateSupervisionStateTest < ActiveSupport::TestCase
  test "projects task rollups and active plan items into durable conversation supervision state" do
    context = build_agent_control_context!
    agent_task_run = create_agent_task_run!(
      workflow_node: context[:workflow_node],
      lifecycle_state: "running",
      started_at: Time.current,
      supervision_state: "running",
      focus_kind: "implementation",
      request_summary: "Replace the observation schema",
      current_focus_summary: "Adding the canonical supervision aggregates",
      recent_progress_summary: "Finished reviewing the old models",
      next_step_hint: "Rewrite the migrations",
      last_progress_at: Time.current,
      supervision_payload: {}
    )
    AgentTaskPlanItem.create!(
      installation: context[:installation],
      agent_task_run: agent_task_run,
      item_key: "projection",
      title: "Add conversation supervision state",
      status: "completed",
      position: 0,
      details_payload: {}
    )
    AgentTaskPlanItem.create!(
      installation: context[:installation],
      agent_task_run: agent_task_run,
      item_key: "renderer",
      title: "Rebuild sidechat renderer",
      status: "in_progress",
      position: 1,
      details_payload: {}
    )
    AgentTaskProgressEntry.create!(
      installation: context[:installation],
      agent_task_run: agent_task_run,
      sequence: 1,
      entry_kind: "progress_recorded",
      summary: "Finished reviewing the old models",
      details_payload: {},
      occurred_at: Time.current
    )

    state = Conversations::UpdateSupervisionState.call(
      conversation: context[:conversation],
      occurred_at: Time.current
    )

    assert_equal "running", state.overall_state
    assert_equal "agent_task_run", state.current_owner_kind
    assert_equal agent_task_run.public_id, state.current_owner_public_id
    assert_equal "Replace the observation schema", state.request_summary
    assert_equal "Adding the canonical supervision aggregates", state.current_focus_summary
    assert_equal "Finished reviewing the old models", state.recent_progress_summary
    assert_equal "Rewrite the migrations", state.next_step_hint
    assert_equal %w[projection renderer],
      state.status_payload.fetch("active_plan_items").map { |item| item.fetch("item_key") }
  end

  test "summarizes subagent barrier waits without leaking raw workflow tokens" do
    context = build_agent_control_context!
    child_conversation = create_conversation_record!(
      workspace: context[:workspace],
      installation: context[:installation],
      parent_conversation: context[:conversation],
      execution_runtime: context[:execution_runtime],
      agent_program_version: context[:agent_program_version],
      kind: "fork",
      addressability: "agent_addressable"
    )
    SubagentSession.create!(
      installation: context[:installation],
      owner_conversation: context[:conversation],
      conversation: child_conversation,
      scope: "conversation",
      profile_key: "worker",
      depth: 0,
      observed_status: "running",
      supervision_state: "running",
      current_focus_summary: "Investigating alpha",
      last_progress_at: Time.current,
      supervision_payload: {}
    )
    context[:workflow_run].update!(
      wait_state: "waiting",
      wait_reason_kind: "subagent_barrier",
      wait_reason_payload: {},
      waiting_since_at: Time.current,
      blocking_resource_type: "SubagentBarrier",
      blocking_resource_id: "barrier-1"
    )

    state = Conversations::UpdateSupervisionState.call(
      conversation: context[:conversation],
      occurred_at: Time.current
    )

    assert_equal "waiting", state.overall_state
    assert state.waiting_summary.present?
    refute_includes state.waiting_summary, "subagent_barrier"
    assert_includes state.waiting_summary.downcase, "child"
    assert_equal ["Investigating alpha"],
      state.status_payload.fetch("active_subagents").map { |entry| entry.fetch("current_focus_summary") }
  end
end
