require "test_helper"

class Conversations::UpdateSupervisionStateTest < ActiveSupport::TestCase
  include ConversationSupervisionFixtureBuilder

  test "projects task rollups and active plan items into durable conversation supervision state" do
    context = build_agent_control_context!
    agent_task_run = create_agent_task_run!(
      workflow_node: context[:workflow_node],
      lifecycle_state: "running",
      started_at: Time.current,
      supervision_state: "running",
      focus_kind: "implementation",
      request_summary: "Stale task request summary",
      current_focus_summary: "Stale task focus summary",
      recent_progress_summary: "Finished reviewing the old models",
      next_step_hint: "Rewrite the migrations",
      last_progress_at: Time.current,
      supervision_payload: {}
    )
    TurnTodoPlans::ApplyUpdate.call(
      agent_task_run: agent_task_run,
      payload: {
        "goal_summary" => "Replace the observation schema",
        "current_item_key" => "renderer",
        "items" => [
          {
            "item_key" => "projection",
            "title" => "Add conversation supervision state",
            "status" => "completed",
            "position" => 0,
            "kind" => "implementation",
          },
          {
            "item_key" => "renderer",
            "title" => "Rebuild sidechat renderer",
            "status" => "in_progress",
            "position" => 1,
            "kind" => "implementation",
          },
        ],
      },
      occurred_at: Time.current
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
    assert_equal "Rebuild sidechat renderer", state.current_focus_summary
    assert_equal "Started rebuild sidechat renderer.", state.recent_progress_summary
    assert_equal "Rewrite the migrations", state.next_step_hint
    assert_equal "active", state.board_lane
    assert_equal 1, state.active_plan_item_count
    assert_equal 1, state.completed_plan_item_count
    assert_equal 0, state.active_subagent_count
    refute state.status_payload.key?("active_plan_items")
    assert_equal "renderer", state.status_payload.fetch("current_turn_plan_summary").fetch("current_item_key")
  end

  test "projects supervision summaries from the active turn todo plan" do
    fixture = build_supervision_with_turn_todo_plan_fixture!

    state = Conversations::UpdateSupervisionState.call(
      conversation: fixture.fetch(:conversation),
      occurred_at: Time.current
    )

    assert_equal "running", state.overall_state
    assert_equal "agent_task_run", state.current_owner_kind
    assert_equal fixture.fetch(:agent_task_run).public_id, state.current_owner_public_id
    assert_equal "Replace AgentTaskPlanItem with TurnTodoPlan", state.request_summary
    assert_equal "Wire plan views into supervision", state.current_focus_summary
    assert_equal "active", state.board_lane
    assert_equal 1, state.active_plan_item_count
    assert_equal 1, state.completed_plan_item_count
    assert_equal "wire-supervision",
      state.status_payload.fetch("current_turn_plan_summary").fetch("current_item_key")
    assert_equal ["check-hard-gate"],
      state.status_payload.fetch("active_subagent_turn_plan_summaries").map { |entry| entry.fetch("current_item_key") }
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

    assert_equal ["turn_started"], feed.map { |entry| entry.fetch("event_kind") }
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
      agent_snapshot: context[:agent_snapshot],
      kind: "fork",
      addressability: "agent_addressable"
    )
    SubagentConnection.create!(
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
      agent: context[:agent]
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

  test "leaves contextual focus summary for lazy sidechat rendering when no task summary exists yet" do
    context = build_agent_control_context!
    context[:turn].selected_input_message.update!(
      content: "Build a complete browser-playable React 2048 game and add automated tests."
    )

    state = Conversations::UpdateSupervisionState.call(
      conversation: context[:conversation],
      occurred_at: Time.current
    )

    assert_equal "queued", state.overall_state
    assert_nil state.current_focus_summary
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
      decision_source: "agent",
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

  test "falls back to coarse generic supervision when provider-backed work has no persisted turn todo plan" do
    fixture = prepare_provider_backed_conversation_supervision_context!

    state = Conversations::UpdateSupervisionState.call(
      conversation: fixture.fetch(:conversation),
      occurred_at: Time.current
    )

    assert_equal "running", state.overall_state
    assert_equal "workflow_run", state.current_owner_kind
    assert state.request_summary.present?
    assert_nil state.status_payload["current_turn_plan_summary"]
    assert_equal "Monitoring a running shell command in /workspace/game-2048", state.current_focus_summary
    assert_equal "A shell command finished in /workspace/game-2048.", state.recent_progress_summary
    assert_equal fixture.fetch(:active_command_run).public_id,
      state.status_payload.dig("runtime_evidence", "active_command", "command_run_public_id")
    refute_match(/React app|game files|test-and-build|preview server|command_run_wait|provider round/i, state.attributes.to_json)
  end

  test "uses the task-run work-state report before coarse runtime fallback when no turn todo plan exists" do
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
  end

  test "keeps task-backed fallback on basic work-state instead of runtime evidence when no plan exists" do
    context = build_agent_control_context!
    agent_task_run = create_agent_task_run!(
      workflow_node: context[:workflow_node],
      lifecycle_state: "running",
      started_at: Time.current,
      supervision_state: "running",
      request_summary: "Replace the observation schema",
      last_progress_at: Time.current,
      supervision_payload: {}
    )

    state = Conversations::UpdateSupervisionState.call(
      conversation: context[:conversation],
      occurred_at: Time.current
    )

    assert_equal "running", state.overall_state
    assert_equal "agent_task_run", state.current_owner_kind
    assert_equal agent_task_run.public_id, state.current_owner_public_id
    assert_equal "Replace the observation schema", state.request_summary
    assert_equal "Working through the current turn", state.current_focus_summary
    assert_nil state.recent_progress_summary
    assert_nil state.status_payload["runtime_evidence"]
  end

  test "prefers generic runtime focus over the basic current-turn fallback when task work-state is blank" do
    fixture = prepare_provider_backed_conversation_supervision_context!
    agent_task_run = create_agent_task_run!(
      workflow_node: fixture.fetch(:active_tool_node),
      lifecycle_state: "running",
      started_at: Time.current,
      supervision_state: "running",
      request_summary: "Replace the observation schema",
      last_progress_at: Time.current,
      supervision_payload: {}
    )

    state = Conversations::UpdateSupervisionState.call(
      conversation: fixture.fetch(:conversation),
      occurred_at: Time.current
    )

    assert_equal "running", state.overall_state
    assert_equal "agent_task_run", state.current_owner_kind
    assert_equal agent_task_run.public_id, state.current_owner_public_id
    assert_equal "Replace the observation schema", state.request_summary
    assert_equal "Monitoring a running shell command in /workspace/game-2048", state.current_focus_summary
    assert_nil state.recent_progress_summary
    assert_nil state.status_payload["runtime_evidence"]
  end

  test "can skip runtime evidence queries for basic task-start fallback" do
    fixture = prepare_provider_backed_conversation_supervision_context!
    agent_task_run = create_agent_task_run!(
      workflow_node: fixture.fetch(:active_tool_node),
      lifecycle_state: "running",
      started_at: Time.current,
      supervision_state: "running",
      request_summary: "Replace the observation schema",
      last_progress_at: Time.current,
      supervision_payload: {}
    )

    state = Conversations::UpdateSupervisionState.call(
      conversation: fixture.fetch(:conversation),
      occurred_at: Time.current,
      include_runtime_evidence: false
    )

    assert_equal "running", state.overall_state
    assert_equal "agent_task_run", state.current_owner_kind
    assert_equal agent_task_run.public_id, state.current_owner_public_id
    assert_equal "Replace the observation schema", state.request_summary
    assert_equal "Working through the current turn", state.current_focus_summary
    assert_nil state.recent_progress_summary
    assert_nil state.status_payload["runtime_evidence"]
  end

  test "surfaces a running process as generic runtime evidence" do
    context = build_agent_control_context!(workflow_node_type: "background_service")
    context[:workflow_node].update!(
      lifecycle_state: "running",
      started_at: 30.seconds.ago,
      presentation_policy: "ops_trackable",
      decision_source: "agent",
      metadata: {}
    )
    process_run = create_process_run!(
      workflow_node: context[:workflow_node],
      installation: context[:installation],
      execution_runtime: context[:execution_runtime],
      lifecycle_state: "running",
      command_line: "cd /workspace/game-2048 && npm run dev -- --host 0.0.0.0 --port 4173",
      started_at: 20.seconds.ago
    )

    state = Conversations::UpdateSupervisionState.call(
      conversation: context[:conversation],
      occurred_at: Time.current
    )

    assert_equal "Monitoring a running process in /workspace/game-2048", state.current_focus_summary
    assert_nil state.recent_progress_summary
    assert_equal process_run.public_id,
      state.status_payload.dig("runtime_evidence", "active_process", "process_run_public_id")
    refute_match(/app server|preview server|React app/i, state.attributes.to_json)
  end

  test "treats active workspace inspection as generic runtime evidence" do
    context = build_agent_control_context!(workflow_node_type: "workspace_scan")
    context[:workflow_node].update!(
      lifecycle_state: "running",
      started_at: 30.seconds.ago,
      presentation_policy: "ops_trackable",
      decision_source: "agent",
      metadata: {}
    )
    command_execution = create_exec_command_execution!(
      context: context,
      workflow_node: context[:workflow_node],
      command_line: "cd /workspace && ls",
      tool_status: "running",
      command_state: "running",
      started_at: 20.seconds.ago
    )

    state = Conversations::UpdateSupervisionState.call(
      conversation: context[:conversation],
      occurred_at: Time.current
    )

    assert_equal "Monitoring a running shell command in /workspace", state.current_focus_summary
    assert_nil state.recent_progress_summary
    assert_equal command_execution.fetch(:command_run).public_id,
      state.status_payload.dig("runtime_evidence", "active_command", "command_run_public_id")
    refute_match(/Wait for the workspace|Inspect the workspace/i, state.attributes.to_json)
  end

  test "keeps waiting scaffolding commands generic when no persisted plan exists" do
    context = build_agent_control_context!
    context[:workflow_node].update!(
      lifecycle_state: "completed",
      started_at: 2.minutes.ago,
      finished_at: 90.seconds.ago,
      presentation_policy: "ops_trackable",
      decision_source: "agent",
      provider_round_index: 1,
      metadata: {}
    )
    running_command_node = create_workflow_node!(
      workflow_run: context[:workflow_run],
      installation: context[:installation],
      node_key: "provider_round_2_tool_1",
      node_type: "tool_call",
      lifecycle_state: "running",
      started_at: 20.seconds.ago,
      presentation_policy: "ops_trackable",
      decision_source: "agent",
      provider_round_index: 2,
      metadata: {}
    )
    command_execution = create_exec_command_execution!(
      context: context,
      workflow_node: running_command_node,
      command_line: "cd /workspace && npm create vite@latest game-2048 -- --template react-ts",
      tool_status: "running",
      command_state: "running",
      started_at: 20.seconds.ago
    )
    create_workflow_node!(
      workflow_run: context[:workflow_run],
      installation: context[:installation],
      node_key: "provider_round_2_tool_2",
      node_type: "tool_call",
      lifecycle_state: "running",
      started_at: 10.seconds.ago,
      presentation_policy: "ops_trackable",
      decision_source: "agent",
      provider_round_index: 2,
      tool_call_document: JsonDocuments::Store.call(
        installation: context[:installation],
        document_kind: "workflow_node_tool_call",
        payload: {
          "call_id" => "call-#{next_test_sequence}",
          "tool_name" => "command_run_wait",
          "request_payload" => {
            "arguments" => { "command_run_id" => command_execution.fetch(:command_run).public_id },
          },
        }
      ),
      metadata: {}
    )

    state = Conversations::UpdateSupervisionState.call(
      conversation: context[:conversation],
      occurred_at: Time.current
    )

    assert_equal "Monitoring a running shell command in /workspace", state.current_focus_summary
    assert_nil state.recent_progress_summary
    assert_equal command_execution.fetch(:command_run).public_id,
      state.status_payload.dig("runtime_evidence", "active_command", "command_run_public_id")
    refute_match(/React app scaffold|scaffolding|command_run_wait/i, state.attributes.to_json)
  end

  test "keeps runtime focus generic even when the conversation request is specific" do
    context = build_agent_control_context!(workflow_node_type: "background_service")
    context[:turn].selected_input_message.update!(
      content: "Build a complete browser-playable React 2048 game in `/workspace/game-2048`."
    )
    context[:workflow_node].update!(
      lifecycle_state: "running",
      started_at: 20.seconds.ago,
      presentation_policy: "ops_trackable",
      decision_source: "agent",
      metadata: {}
    )
    process_run = create_process_run!(
      workflow_node: context[:workflow_node],
      installation: context[:installation],
      execution_runtime: context[:execution_runtime],
      lifecycle_state: "running",
      command_line: "cd /workspace/game-2048 && npm run preview",
      started_at: 20.seconds.ago
    )
    create_workflow_node!(
      workflow_run: context[:workflow_run],
      installation: context[:installation],
      node_key: "provider_round_2",
      node_type: "turn_step",
      lifecycle_state: "running",
      started_at: 10.seconds.ago,
      presentation_policy: "ops_trackable",
      decision_source: "agent",
      provider_round_index: 2,
      metadata: {}
    )

    state = Conversations::UpdateSupervisionState.call(
      conversation: context[:conversation],
      occurred_at: Time.current
    )

    assert_equal "Monitoring a running process in /workspace/game-2048", state.current_focus_summary
    assert_nil state.recent_progress_summary
    assert_nil state.status_payload["current_turn_plan_summary"]
    assert_equal process_run.public_id,
      state.status_payload.dig("runtime_evidence", "active_process", "process_run_public_id")
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
    assert_equal "The turn completed.", state.recent_progress_summary
  end

  test "clears stale runtime focus summaries once completed workflow work is idle" do
    context = build_agent_control_context!(workflow_node_type: "background_service")
    context[:turn].selected_input_message.update!(
      content: "Build a complete browser-playable React 2048 game in `/workspace/game-2048`."
    )
    context[:workflow_node].update!(
      lifecycle_state: "completed",
      started_at: 20.seconds.ago,
      finished_at: 5.seconds.ago,
      presentation_policy: "ops_trackable",
      decision_source: "agent",
      metadata: {}
    )
    create_process_run!(
      workflow_node: context[:workflow_node],
      installation: context[:installation],
      execution_runtime: context[:execution_runtime],
      lifecycle_state: "stopped",
      command_line: "cd /workspace/game-2048 && npm run preview",
      started_at: 20.seconds.ago,
      ended_at: 5.seconds.ago
    )
    context[:workflow_run].update!(lifecycle_state: "completed")
    context[:turn].update!(lifecycle_state: "completed")

    state = Conversations::UpdateSupervisionState.call(
      conversation: context[:conversation],
      occurred_at: Time.current
    )

    assert_equal "idle", state.overall_state
    assert_nil state.current_focus_summary
    assert_nil state.waiting_summary
    assert_nil state.status_payload["runtime_evidence"]
    assert_equal "The turn completed.", state.recent_progress_summary
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
    assert_equal "The turn failed.", state.recent_progress_summary
  end

  test "prefers an active conversation subagent connection over a historical terminal task" do
    parent_context = build_agent_control_context!
    child_conversation = create_conversation_record!(
      workspace: parent_context[:workspace],
      installation: parent_context[:installation],
      parent_conversation: parent_context[:conversation],
      execution_runtime: parent_context[:execution_runtime],
      agent_snapshot: parent_context[:agent_snapshot],
      kind: "fork",
      addressability: "agent_addressable"
    )
    subagent_connection = SubagentConnection.create!(
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
      agent: parent_context[:agent],
      subagent_connection: subagent_connection,
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
    assert_equal "subagent_connection", state.current_owner_kind
    assert_equal subagent_connection.public_id, state.current_owner_public_id
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
      agent_snapshot: context[:agent_snapshot],
      kind: "fork",
      addressability: "agent_addressable"
    )
    unrelated_conversation = create_conversation_record!(
      workspace: context[:workspace],
      installation: context[:installation],
      parent_conversation: context[:conversation],
      execution_runtime: context[:execution_runtime],
      agent_snapshot: context[:agent_snapshot],
      kind: "fork",
      addressability: "agent_addressable"
    )
    barrier_session = SubagentConnection.create!(
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
    SubagentConnection.create!(
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
      spawned_subagent_connection: barrier_session,
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

  private

  def build_supervision_with_turn_todo_plan_fixture!
    context = build_agent_control_context!
    agent_task_run = create_agent_task_run!(
      workflow_node: context[:workflow_node],
      lifecycle_state: "running",
      started_at: 3.minutes.ago,
      supervision_state: "running",
      request_summary: "Stale legacy request summary",
      current_focus_summary: "Stale legacy focus summary",
      recent_progress_summary: "Finished reviewing the old models",
      next_step_hint: "Rewrite the migrations",
      last_progress_at: 1.minute.ago,
      supervision_payload: {}
    )
    TurnTodoPlans::ApplyUpdate.call(
      agent_task_run: agent_task_run,
      payload: {
        "goal_summary" => "Replace AgentTaskPlanItem with TurnTodoPlan",
        "current_item_key" => "wire-supervision",
        "items" => [
          {
            "item_key" => "define-domain",
            "title" => "Define the new plan domain",
            "status" => "completed",
            "position" => 0,
            "kind" => "implementation",
          },
          {
            "item_key" => "wire-supervision",
            "title" => "Wire plan views into supervision",
            "status" => "in_progress",
            "position" => 1,
            "kind" => "implementation",
          },
        ],
      },
      occurred_at: 1.minute.ago
    )
    AgentTaskProgressEntry.create!(
      installation: context[:installation],
      agent_task_run: agent_task_run,
      sequence: 1,
      entry_kind: "progress_recorded",
      summary: "Finished reviewing the old models",
      details_payload: {},
      occurred_at: 1.minute.ago
    )

    child_conversation = create_conversation_record!(
      workspace: context[:workspace],
      installation: context[:installation],
      parent_conversation: context[:conversation],
      execution_runtime: context[:execution_runtime],
      agent_snapshot: context[:agent_snapshot],
      kind: "fork",
      addressability: "agent_addressable"
    )
    subagent_connection = SubagentConnection.create!(
      installation: context[:installation],
      owner_conversation: context[:conversation],
      conversation: child_conversation,
      scope: "conversation",
      profile_key: "researcher",
      depth: 0,
      observed_status: "running",
      supervision_state: "running",
      request_summary: "Stale child request summary",
      current_focus_summary: "Stale child focus summary",
      recent_progress_summary: "Confirmed the control acceptance wiring",
      last_progress_at: 30.seconds.ago,
      supervision_payload: {}
    )
    child_turn = Turns::StartAgentTurn.call(
      conversation: child_conversation,
      content: "Verify the acceptance flow",
      sender_kind: "owner_agent",
      sender_conversation: context[:conversation],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    child_workflow_run = create_workflow_run!(
      installation: context[:installation],
      conversation: child_conversation,
      turn: child_turn,
      lifecycle_state: "active"
    )
    child_workflow_node = create_workflow_node!(
      workflow_run: child_workflow_run,
      installation: context[:installation],
      node_key: "subagent_step",
      node_type: "subagent_step",
      lifecycle_state: "running",
      started_at: 2.minutes.ago
    )
    child_agent_task_run = create_agent_task_run!(
      installation: context[:installation],
      workflow_run: child_workflow_run,
      workflow_node: child_workflow_node,
      conversation: child_conversation,
      turn: child_turn,
      agent: context[:agent],
      subagent_connection: subagent_connection,
      origin_turn: context[:turn],
      kind: "subagent_step",
      lifecycle_state: "running",
      started_at: 2.minutes.ago,
      supervision_state: "running",
      request_summary: "Stale child request summary",
      current_focus_summary: "Stale child focus summary",
      last_progress_at: 30.seconds.ago,
      supervision_payload: {}
    )
    TurnTodoPlans::ApplyUpdate.call(
      agent_task_run: child_agent_task_run,
      payload: {
        "goal_summary" => "Verify the acceptance flow",
        "current_item_key" => "check-hard-gate",
        "items" => [
          {
            "item_key" => "check-hard-gate",
            "title" => "Check the 2048 hard gate",
            "status" => "in_progress",
            "position" => 0,
            "kind" => "verification",
          },
        ],
      },
      occurred_at: 30.seconds.ago
    )

    {
      conversation: context[:conversation],
      agent_task_run: agent_task_run,
      subagent_connection: subagent_connection,
      child_agent_task_run: child_agent_task_run,
    }
  end
end
