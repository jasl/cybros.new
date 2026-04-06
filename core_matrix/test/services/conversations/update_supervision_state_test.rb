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
    assert_equal "active", state.board_lane
    assert_equal 1, state.active_plan_item_count
    assert_equal 1, state.completed_plan_item_count
    assert_equal 0, state.active_subagent_count
    assert_equal %w[projection renderer],
      state.status_payload.fetch("active_plan_items").map { |item| item.fetch("item_key") }
  end

  test "appends semantic feed entries from supervision changes" do
    context = build_agent_control_context!
    agent_task_run = create_agent_task_run!(
      workflow_node: context[:workflow_node],
      lifecycle_state: "running",
      started_at: Time.current,
      supervision_state: "running",
      request_summary: "Replace the observation schema",
      current_focus_summary: "Adding the canonical supervision aggregates",
      recent_progress_summary: "Finished reviewing the old models",
      last_progress_at: Time.current,
      supervision_payload: {}
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

    Conversations::UpdateSupervisionState.call(
      conversation: context[:conversation],
      occurred_at: Time.current
    )

    feed = ConversationSupervision::BuildActivityFeed.call(conversation: context[:conversation])

    assert_equal %w[turn_started progress_recorded], feed.map { |entry| entry.fetch("event_kind") }
    assert_equal ["Finished reviewing the old models"], feed.select { |entry| entry.fetch("event_kind") == "progress_recorded" }.map { |entry| entry.fetch("summary") }
    assert_equal [context[:turn].public_id], feed.map { |entry| entry.fetch("turn_id") }.uniq
  end

  test "suppresses detailed summaries and semantic feed when the conversation only allows coarse supervision" do
    context = build_agent_control_context!
    ConversationCapabilityPolicy.create!(
      installation: context[:installation],
      target_conversation: context[:conversation],
      supervision_enabled: true,
      detailed_progress_enabled: false,
      side_chat_enabled: true,
      control_enabled: false,
      policy_payload: {}
    )
    agent_task_run = create_agent_task_run!(
      workflow_node: context[:workflow_node],
      lifecycle_state: "running",
      started_at: Time.current,
      supervision_state: "running",
      request_summary: "Replace the observation schema",
      current_focus_summary: "Adding the canonical supervision aggregates",
      recent_progress_summary: "Finished reviewing the old models",
      next_step_hint: "Rewrite the migrations",
      last_progress_at: Time.current,
      supervision_payload: {}
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
    assert_nil state.request_summary
    assert_nil state.current_focus_summary
    assert_nil state.recent_progress_summary
    assert_nil state.next_step_hint
    assert_empty ConversationSupervision::BuildActivityFeed.call(conversation: context[:conversation])
  end

  test "does not append duplicate feed entries when the semantic supervision state is unchanged" do
    context = build_agent_control_context!
    agent_task_run = create_agent_task_run!(
      workflow_node: context[:workflow_node],
      lifecycle_state: "running",
      started_at: Time.current,
      supervision_state: "running",
      request_summary: "Replace the observation schema",
      current_focus_summary: "Adding the canonical supervision aggregates",
      recent_progress_summary: "Finished reviewing the old models",
      last_progress_at: Time.current,
      supervision_payload: {}
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

    Conversations::UpdateSupervisionState.call(
      conversation: context[:conversation],
      occurred_at: Time.current
    )
    initial_count = ConversationSupervisionFeedEntry.where(target_conversation: context[:conversation]).count

    Conversations::UpdateSupervisionState.call(
      conversation: context[:conversation],
      occurred_at: Time.current
    )

    assert_equal initial_count,
      ConversationSupervisionFeedEntry.where(target_conversation: context[:conversation]).count
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
    assert_equal "handoff", state.board_lane
    assert_equal 1, state.active_subagent_count
    assert state.waiting_summary.present?
    refute_includes state.waiting_summary, "subagent_barrier"
    assert_includes state.waiting_summary.downcase, "child"
    assert_equal ["Investigating alpha"],
      state.status_payload.fetch("active_subagents").map { |entry| entry.fetch("current_focus_summary") }
  end

  test "projects idle for a new conversation with no active work" do
    context = create_workspace_context!
    conversation = create_conversation_record!(
      workspace: context[:workspace],
      installation: context[:installation],
      execution_runtime: context[:execution_runtime],
      agent_program: context[:agent_program]
    )

    state = Conversations::UpdateSupervisionState.call(
      conversation: conversation,
      occurred_at: Time.current
    )

    assert_equal "idle", state.overall_state
    assert_equal "idle", state.board_lane
    assert_nil state.last_terminal_state
    assert_nil state.last_terminal_at
  end

  test "projects queued while the conversation still has active turn work to schedule" do
    context = build_agent_control_context!

    state = Conversations::UpdateSupervisionState.call(
      conversation: context[:conversation],
      occurred_at: Time.current
    )

    assert_equal "queued", state.overall_state
    assert_equal "queued", state.board_lane
    assert_equal "workflow_run", state.current_owner_kind
    assert_equal context[:workflow_run].public_id, state.current_owner_public_id
  end

  test "derives a contextual focus summary from the active turn when no task summary exists yet" do
    context = build_agent_control_context!
    context[:turn].selected_input_message.update!(
      content: "Build a complete browser-playable React 2048 game and add automated tests."
    )

    state = Conversations::UpdateSupervisionState.call(
      conversation: context[:conversation],
      occurred_at: Time.current
    )

    assert_equal "queued", state.overall_state
    assert_equal "building the React 2048 game", state.current_focus_summary
  end

  test "projects running when an active workflow is already advancing without a task run projection" do
    context = build_agent_control_context!
    context[:workflow_node].update!(
      lifecycle_state: "completed",
      started_at: 2.minutes.ago,
      finished_at: 1.minute.ago
    )
    create_workflow_node!(
      workflow_run: context[:workflow_run],
      installation: context[:installation],
      node_key: "provider_round_2",
      node_type: "turn_step",
      lifecycle_state: "running",
      started_at: 30.seconds.ago,
      presentation_policy: "ops_trackable",
      decision_source: "agent_program",
      metadata: {}
    )

    state = Conversations::UpdateSupervisionState.call(
      conversation: context[:conversation],
      occurred_at: Time.current
    )

    assert_equal "running", state.overall_state
    assert_equal "active", state.board_lane
    assert_equal "workflow_run", state.current_owner_kind
    assert_equal context[:workflow_run].public_id, state.current_owner_public_id
  end

  test "projects idle with last terminal completed when the previous run finished and nothing is active" do
    context = build_agent_control_context!
    context[:workflow_run].update!(lifecycle_state: "completed")
    context[:turn].update!(lifecycle_state: "completed")
    agent_task_run = create_agent_task_run!(
      workflow_node: context[:workflow_node],
      lifecycle_state: "completed",
      started_at: 2.minutes.ago,
      finished_at: 1.minute.ago,
      supervision_state: "completed",
      focus_kind: "implementation",
      last_progress_at: 1.minute.ago,
      supervision_payload: {}
    )

    state = Conversations::UpdateSupervisionState.call(
      conversation: context[:conversation],
      occurred_at: Time.current
    )

    assert_equal "idle", state.overall_state
    assert_equal "idle", state.board_lane
    assert_equal "completed", state.last_terminal_state
    assert_equal agent_task_run.finished_at.to_i, state.last_terminal_at.to_i
  end

  test "projects idle with last terminal failed when the previous run failed and nothing is active" do
    context = build_agent_control_context!
    context[:workflow_run].update!(lifecycle_state: "failed")
    context[:turn].update!(lifecycle_state: "failed")
    agent_task_run = create_agent_task_run!(
      workflow_node: context[:workflow_node],
      lifecycle_state: "failed",
      started_at: 2.minutes.ago,
      finished_at: 1.minute.ago,
      supervision_state: "failed",
      focus_kind: "implementation",
      blocked_summary: "Provider timed out",
      last_progress_at: 1.minute.ago,
      supervision_payload: {}
    )

    state = Conversations::UpdateSupervisionState.call(
      conversation: context[:conversation],
      occurred_at: Time.current
    )

    assert_equal "idle", state.overall_state
    assert_equal "idle", state.board_lane
    assert_equal "failed", state.last_terminal_state
    assert_equal agent_task_run.finished_at.to_i, state.last_terminal_at.to_i
  end

  test "prefers an active conversation subagent session over a historical terminal task" do
    parent_context = build_agent_control_context!
    child_conversation = create_conversation_record!(
      workspace: parent_context[:workspace],
      installation: parent_context[:installation],
      parent_conversation: parent_context[:conversation],
      execution_runtime: parent_context[:execution_runtime],
      agent_program_version: parent_context[:agent_program_version],
      kind: "fork",
      addressability: "agent_addressable"
    )
    subagent_session = SubagentSession.create!(
      installation: parent_context[:installation],
      owner_conversation: parent_context[:conversation],
      conversation: child_conversation,
      scope: "conversation",
      profile_key: "worker",
      depth: 0,
      observed_status: "running",
      supervision_state: "running",
      request_summary: "Investigate alpha",
      current_focus_summary: "Continuing reusable child work",
      last_progress_at: 1.minute.ago,
      supervision_payload: {}
    )
    child_turn = Turns::StartAgentTurn.call(
      conversation: child_conversation,
      content: "Investigate alpha",
      sender_kind: "owner_agent",
      sender_conversation: parent_context[:conversation],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    child_workflow_run = create_workflow_run!(
      installation: parent_context[:installation],
      conversation: child_conversation,
      turn: child_turn,
      lifecycle_state: "active"
    )
    child_workflow_node = create_workflow_node!(
      workflow_run: child_workflow_run,
      installation: parent_context[:installation],
      node_key: "subagent_step",
      node_type: "subagent_step",
      lifecycle_state: "completed",
      started_at: 3.minutes.ago,
      finished_at: 2.minutes.ago
    )
    create_agent_task_run!(
      installation: parent_context[:installation],
      workflow_run: child_workflow_run,
      workflow_node: child_workflow_node,
      conversation: child_conversation,
      turn: child_turn,
      agent_program: parent_context[:agent_program],
      subagent_session: subagent_session,
      origin_turn: parent_context[:turn],
      kind: "subagent_step",
      lifecycle_state: "completed",
      started_at: 3.minutes.ago,
      finished_at: 2.minutes.ago,
      supervision_state: "completed",
      request_summary: "Investigate alpha",
      recent_progress_summary: "Finished the first pass",
      last_progress_at: 2.minutes.ago,
      supervision_payload: {}
    )

    state = Conversations::UpdateSupervisionState.call(
      conversation: child_conversation,
      occurred_at: Time.current
    )

    assert_equal "running", state.overall_state
    assert_equal "subagent_session", state.current_owner_kind
    assert_equal subagent_session.public_id, state.current_owner_public_id
    assert_equal "Continuing reusable child work", state.current_focus_summary
  end

  test "subagent barrier summaries only include sessions attached to the blocking barrier" do
    context = build_agent_control_context!
    yielding_node = context[:workflow_node]

    barrier_conversation = create_conversation_record!(
      workspace: context[:workspace],
      installation: context[:installation],
      parent_conversation: context[:conversation],
      execution_runtime: context[:execution_runtime],
      agent_program_version: context[:agent_program_version],
      kind: "fork",
      addressability: "agent_addressable"
    )
    unrelated_conversation = create_conversation_record!(
      workspace: context[:workspace],
      installation: context[:installation],
      parent_conversation: context[:conversation],
      execution_runtime: context[:execution_runtime],
      agent_program_version: context[:agent_program_version],
      kind: "fork",
      addressability: "agent_addressable"
    )
    barrier_session = SubagentSession.create!(
      installation: context[:installation],
      owner_conversation: context[:conversation],
      conversation: barrier_conversation,
      scope: "conversation",
      profile_key: "worker",
      depth: 0,
      observed_status: "running",
      supervision_state: "running",
      current_focus_summary: "Barrier child",
      last_progress_at: 1.minute.ago,
      supervision_payload: {}
    )
    SubagentSession.create!(
      installation: context[:installation],
      owner_conversation: context[:conversation],
      conversation: unrelated_conversation,
      scope: "conversation",
      profile_key: "worker",
      depth: 0,
      observed_status: "running",
      supervision_state: "running",
      current_focus_summary: "Unrelated child",
      last_progress_at: 30.seconds.ago,
      supervision_payload: {}
    )
    create_workflow_node!(
      workflow_run: context[:workflow_run],
      installation: context[:installation],
      node_key: "subagent_alpha",
      node_type: "subagent_spawn",
      lifecycle_state: "completed",
      intent_kind: "subagent_spawn",
      intent_batch_id: "batch-subagents-1",
      intent_id: "intent-subagent-1",
      intent_requirement: "required",
      stage_index: 0,
      stage_position: 0,
      yielding_workflow_node: yielding_node,
      spawned_subagent_session: barrier_session,
      started_at: 2.minutes.ago,
      finished_at: 90.seconds.ago
    )
    WorkflowArtifact.create!(
      installation: context[:installation],
      workflow_run: context[:workflow_run],
      workflow_node: yielding_node,
      artifact_key: "barrier-1",
      artifact_kind: "intent_batch_barrier",
      storage_mode: "json_document",
      payload: {
        "batch_id" => "batch-subagents-1",
        "stage" => {
          "stage_index" => 0,
          "dispatch_mode" => "parallel",
          "completion_barrier" => "wait_all",
        },
        "accepted_intent_ids" => ["intent-subagent-1"],
        "rejected_intent_ids" => [],
      }
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
    assert_includes state.waiting_summary, "1 child task"
    assert_includes state.waiting_summary, "Barrier child"
    refute_includes state.waiting_summary, "Unrelated child"
  end
end
