require "test_helper"

class AgentControl::HandleExecutionReportTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "maps stale heartbeat timeouts to stale reports without mutating execution progress" do
    context = build_agent_control_context!
    scenario = MailboxScenarioBuilder.new(self).execution_assignment!(context: context)
    mailbox_item = scenario.fetch(:mailbox_item)
    agent_task_run = scenario.fetch(:agent_task_run)
    started_at = Time.zone.parse("2026-03-29 22:00:00 UTC")

    travel_to(started_at) do
      agent_task_run.update!(
        lifecycle_state: "running",
        holder_agent_connection: context[:agent_connection],
        started_at: started_at
      )
      Leases::Acquire.call(
        leased_resource: agent_task_run,
        holder_key: context[:agent_definition_version].public_id,
        heartbeat_timeout_seconds: 30
      )
      mailbox_item.update!(
        status: "acked",
        leased_to_agent_connection: context[:agent_connection],
        leased_at: started_at,
        lease_expires_at: started_at + mailbox_item.lease_timeout_seconds.seconds,
        acked_at: started_at
      )
    end

    assert_raises(AgentControl::Report::StaleReportError) do
      AgentControl::HandleExecutionReport.call(
        agent_definition_version: context[:agent_definition_version],
        method_id: "execution_progress",
        payload: {
          "mailbox_item_id" => mailbox_item.public_id,
          "agent_task_run_id" => agent_task_run.public_id,
          "logical_work_id" => agent_task_run.logical_work_id,
          "attempt_no" => agent_task_run.attempt_no,
          "progress_payload" => { "state" => "late" },
        },
        occurred_at: started_at + 31.seconds
      )
    end

    assert_equal({}, agent_task_run.reload.progress_payload)
    assert_equal "running", agent_task_run.lifecycle_state
    assert_equal "heartbeat_timeout", agent_task_run.execution_lease.reload.release_reason
    assert_not agent_task_run.execution_lease.active?
    assert_equal "acked", mailbox_item.reload.status
  end

  test "execution_progress applies semantic supervision updates and refreshes the conversation projection" do
    context = build_agent_control_context!
    scenario = MailboxScenarioBuilder.new(self).execution_assignment!(context: context)
    mailbox_item = scenario.fetch(:mailbox_item)
    agent_task_run = scenario.fetch(:agent_task_run)

    report_execution_started!(
      agent_definition_version: context.fetch(:agent_definition_version),
      mailbox_item: mailbox_item,
      agent_task_run: agent_task_run
    )

    AgentControl::HandleExecutionReport.call(
      agent_definition_version: context[:agent_definition_version],
      method_id: "execution_progress",
      payload: {
        "mailbox_item_id" => mailbox_item.public_id,
        "agent_task_run_id" => agent_task_run.public_id,
        "logical_work_id" => agent_task_run.logical_work_id,
        "attempt_no" => agent_task_run.attempt_no,
        "progress_payload" => {
          "supervision_update" => {
            "supervision_state" => "running",
            "focus_kind" => "implementation",
            "request_summary" => "Replace the observation schema",
            "current_focus_summary" => "Adding the canonical supervision aggregates",
            "recent_progress_summary" => "Finished reviewing the old models",
            "next_step_hint" => "Rewrite the migrations",
          },
        },
      },
      occurred_at: Time.current
    )

    agent_task_run.reload
    assert_equal "running", agent_task_run.supervision_state
    assert_equal "implementation", agent_task_run.focus_kind
    assert_equal "Replace the observation schema", agent_task_run.request_summary
    assert_equal "Adding the canonical supervision aggregates", agent_task_run.current_focus_summary
    assert_equal "Finished reviewing the old models", agent_task_run.recent_progress_summary
    assert_equal "Rewrite the migrations", agent_task_run.next_step_hint
    assert_equal(
      {
        "supervision_update" => {
          "supervision_state" => "running",
          "focus_kind" => "implementation",
          "request_summary" => "Replace the observation schema",
          "current_focus_summary" => "Adding the canonical supervision aggregates",
          "recent_progress_summary" => "Finished reviewing the old models",
          "next_step_hint" => "Rewrite the migrations",
        },
      },
      agent_task_run.agent_task_run_detail.progress_payload
    )
    assert_equal "Finished reviewing the old models", agent_task_run.agent_task_progress_entries.order(:sequence).last.summary

    supervision_state = context[:conversation].reload.conversation_supervision_state
    assert_equal "running", supervision_state.overall_state
    assert_equal "agent_task_run", supervision_state.current_owner_kind
    assert_equal agent_task_run.public_id, supervision_state.current_owner_public_id
    assert_equal "Adding the canonical supervision aggregates", supervision_state.current_focus_summary
  end

  test "execution_started advances queued supervision and refreshes the conversation projection" do
    context = build_agent_control_context!
    scenario = MailboxScenarioBuilder.new(self).execution_assignment!(context: context)
    mailbox_item = scenario.fetch(:mailbox_item)
    agent_task_run = scenario.fetch(:agent_task_run)

    assert_equal "queued", agent_task_run.supervision_state
    assert_nil context[:conversation].reload.conversation_supervision_state

    report_execution_started!(
      agent_definition_version: context.fetch(:agent_definition_version),
      mailbox_item: mailbox_item,
      agent_task_run: agent_task_run,
      occurred_at: Time.current
    )

    agent_task_run.reload
    supervision_state = context[:conversation].reload.conversation_supervision_state

    assert_equal "running", agent_task_run.supervision_state
    assert agent_task_run.last_progress_at.present?
    assert_equal "running", supervision_state.overall_state
    assert_equal "agent_task_run", supervision_state.current_owner_kind
    assert_equal agent_task_run.public_id, supervision_state.current_owner_public_id
  end

  test "execution_started preserves runtime wait when passed a stale-loaded agent task run" do
    context = build_agent_control_context!
    scenario = MailboxScenarioBuilder.new(self).execution_assignment!(context: context)
    mailbox_item = scenario.fetch(:mailbox_item)
    stale_agent_task_run = AgentTaskRun.find_by!(public_id: scenario.fetch(:agent_task_run).public_id)

    stale_agent_task_run.workflow_run
    stale_agent_task_run.workflow_node

    AgentControl::Poll.call(execution_runtime_connection: context.fetch(:execution_runtime_connection), limit: 10)

    workflow_node = WorkflowNode.find(stale_agent_task_run.workflow_node_id)
    workflow_run = WorkflowRun.find(stale_agent_task_run.workflow_run_id)

    workflow_node.update!(
      lifecycle_state: "waiting",
      started_at: 1.minute.ago,
      finished_at: nil
    )
    workflow_run.turn.update!(lifecycle_state: "waiting")
    workflow_run.update!(
      Workflows::WaitState.cleared_detail_attributes.merge(
        wait_state: "waiting",
        wait_reason_kind: "execution_runtime_request",
        wait_reason_payload: {
          "mailbox_item_id" => mailbox_item.public_id,
          "logical_work_id" => stale_agent_task_run.logical_work_id,
          "request_kind" => "execute_tool",
        },
        wait_resume_mode: "same_step",
        waiting_since_at: Time.current,
        blocking_resource_type: "WorkflowNode",
        blocking_resource_id: workflow_node.public_id
      )
    )

    AgentControl::HandleExecutionReport.call(
      agent_definition_version: context.fetch(:agent_definition_version),
      execution_runtime_connection: context.fetch(:execution_runtime_connection),
      agent_task_run: stale_agent_task_run,
      method_id: "execution_started",
      payload: {
        "mailbox_item_id" => mailbox_item.public_id,
        "agent_task_run_id" => stale_agent_task_run.public_id,
        "logical_work_id" => stale_agent_task_run.logical_work_id,
        "attempt_no" => stale_agent_task_run.attempt_no,
        "expected_duration_seconds" => 30,
      },
      occurred_at: Time.current
    )

    assert_equal "waiting", workflow_node.reload.lifecycle_state
    assert_equal "running", stale_agent_task_run.reload.lifecycle_state
    assert_equal "acked", mailbox_item.reload.status
  end

  test "execution_complete validates against live task state when passed a stale-loaded agent task run" do
    context = build_agent_control_context!
    scenario = MailboxScenarioBuilder.new(self).execution_assignment!(context: context)
    mailbox_item = scenario.fetch(:mailbox_item)
    stale_agent_task_run = AgentTaskRun.find_by!(public_id: scenario.fetch(:agent_task_run).public_id)
    occurred_at = Time.current

    AgentControl::Poll.call(execution_runtime_connection: context.fetch(:execution_runtime_connection), limit: 10, occurred_at: occurred_at)

    live_agent_task_run = AgentTaskRun.find(stale_agent_task_run.id)
    live_agent_task_run.update!(
      lifecycle_state: "running",
      holder_agent_connection: context.fetch(:agent_connection),
      started_at: occurred_at
    )
    Leases::Acquire.call(
      leased_resource: live_agent_task_run,
      holder_key: context.fetch(:agent_definition_version).public_id,
      heartbeat_timeout_seconds: mailbox_item.lease_timeout_seconds
    )

    AgentControl::HandleExecutionReport.call(
      agent_definition_version: context.fetch(:agent_definition_version),
      execution_runtime_connection: context.fetch(:execution_runtime_connection),
      agent_task_run: stale_agent_task_run,
      method_id: "execution_complete",
      payload: {
        "mailbox_item_id" => mailbox_item.public_id,
        "agent_task_run_id" => stale_agent_task_run.public_id,
        "logical_work_id" => stale_agent_task_run.logical_work_id,
        "attempt_no" => stale_agent_task_run.attempt_no,
        "terminal_payload" => { "output" => "Live runtime state was honored." },
      },
      occurred_at: occurred_at + 1.second
    )

    assert_equal "completed", live_agent_task_run.reload.lifecycle_state
    assert_equal "completed", mailbox_item.reload.status
  end

  test "execution_complete resumes blocked workflow nodes waiting on execution-runtime tool calls" do
    runtime_tool = {
      "tool_name" => "memory_search",
      "tool_kind" => "execution_runtime",
      "implementation_source" => "execution_runtime",
      "implementation_ref" => "runtime/memory_search",
      "input_schema" => {
        "type" => "object",
        "properties" => {
          "query" => { "type" => "string" },
        },
      },
      "result_schema" => {
        "type" => "object",
        "properties" => {
          "entries" => { "type" => "array" },
        },
      },
      "streaming_support" => false,
      "idempotency_policy" => "best_effort",
    }
    context = build_governed_tool_context!(
      execution_runtime_tool_catalog: [runtime_tool],
      profile_policy: {
        "main" => {
          "label" => "Main",
          "description" => "Primary interactive profile",
          "allowed_tool_names" => %w[memory_search compact_context subagent_spawn],
        },
      }
    )
    root_node = context.fetch(:workflow_node)
    source_binding = ProviderExecution::MaterializeRoundTools.call(
      workflow_node: root_node,
      tool_catalog: [runtime_tool]
    ).includes(:tool_definition, :tool_implementation).sole

    Workflows::Mutate.call(
      workflow_run: root_node.workflow_run,
      nodes: [
        {
          node_key: "provider_round_1_tool_runtime",
          node_type: "tool_call",
          decision_source: "llm",
          yielding_node_key: root_node.node_key,
          metadata: {},
          tool_call_payload: {
            "call_id" => "call-runtime-1",
            "tool_name" => "memory_search",
            "arguments" => { "query" => "skills" },
            "provider_format" => "chat_completions",
          },
        },
      ],
      edges: [
        {
          from_node_key: root_node.node_key,
          to_node_key: "provider_round_1_tool_runtime",
        },
      ]
    )

    tool_node = root_node.workflow_run.reload.workflow_nodes.find_by!(node_key: "provider_round_1_tool_runtime")

    ToolBinding.create!(
      installation: tool_node.installation,
      workflow_node: tool_node,
      tool_definition: source_binding.tool_definition,
      tool_implementation: source_binding.tool_implementation,
      binding_reason: "snapshot_default",
      runtime_state: source_binding.runtime_state,
      round_scoped: source_binding.round_scoped,
      parallel_safe: source_binding.parallel_safe
    )

    ProviderExecution::ExecuteToolNode.call(workflow_node: tool_node)

    agent_task_run = AgentTaskRun.find_by!(workflow_node: tool_node, kind: "agent_tool_call")
    mailbox_item = AgentControlMailboxItem.find_by!(agent_task_run: agent_task_run, item_type: "execution_assignment")
    tool_invocation = tool_node.tool_invocations.sole

    assert_equal "waiting", tool_node.reload.lifecycle_state
    assert_equal "execution_runtime_request", root_node.workflow_run.reload.wait_reason_kind

    report_execution_started!(
      agent_definition_version: context.fetch(:agent_definition_version),
      mailbox_item: mailbox_item,
      agent_task_run: agent_task_run
    )

    assert_equal "waiting", tool_node.reload.lifecycle_state

    assert_enqueued_with(job: Workflows::ExecuteNodeJob) do
      report_execution_complete!(
        agent_definition_version: context.fetch(:agent_definition_version),
        mailbox_item: mailbox_item,
        agent_task_run: agent_task_run,
        terminal_payload: {
          "tool_invocations" => [
            {
              "event" => "completed",
              "tool_invocation_id" => tool_invocation.public_id,
              "call_id" => "call-runtime-1",
              "tool_name" => "memory_search",
              "response_payload" => {
                "entries" => [],
              },
            },
          ],
          "output" => "Execution runtime completed the requested tool call.",
        }
      )
    end

    workflow_run = root_node.workflow_run.reload

    assert_equal "ready", workflow_run.wait_state
    assert_nil workflow_run.wait_reason_kind
    assert_includes %w[pending queued], tool_node.reload.lifecycle_state
    assert_equal "completed", mailbox_item.reload.status
    assert_equal "succeeded", tool_invocation.reload.status
  end

  test "execution_complete appends a semantic completion entry" do
    assert_terminal_execution_report!(
      method_id: "execution_complete",
      lifecycle_state: "completed",
      entry_kind: "execution_completed",
      projected_overall_state: "queued",
      projected_board_lane: "queued",
      terminal_payload: { "output" => "Shipped the projector" }
    )
  end

  test "execution_fail appends a semantic failure entry" do
    assert_terminal_execution_report!(
      method_id: "execution_fail",
      lifecycle_state: "failed",
      entry_kind: "execution_failed",
      projected_overall_state: "idle",
      projected_board_lane: "idle",
      terminal_payload: { "last_error_summary" => "Provider timed out while saving the projection" }
    )
  end

  test "execution_interrupted appends a semantic interruption entry" do
    assert_terminal_execution_report!(
      method_id: "execution_interrupted",
      lifecycle_state: "interrupted",
      entry_kind: "execution_interrupted",
      projected_overall_state: "queued",
      projected_board_lane: "queued",
      terminal_payload: {}
    )
  end

  test "execution_complete sanitizes unsafe terminal summaries before persisting them" do
    context = build_agent_control_context!
    scenario = MailboxScenarioBuilder.new(self).execution_assignment!(context: context)
    mailbox_item = scenario.fetch(:mailbox_item)
    agent_task_run = scenario.fetch(:agent_task_run)

    report_execution_started!(
      agent_definition_version: context.fetch(:agent_definition_version),
      mailbox_item: mailbox_item,
      agent_task_run: agent_task_run
    )

    unsafe_output = (["provider_round_1_tool_1", "runtime.plan", "Delivered the patch."] * 40).join(" ")

    AgentControl::HandleExecutionReport.call(
      agent_definition_version: context[:agent_definition_version],
      method_id: "execution_complete",
      payload: {
        "mailbox_item_id" => mailbox_item.public_id,
        "agent_task_run_id" => agent_task_run.public_id,
        "logical_work_id" => agent_task_run.logical_work_id,
        "attempt_no" => agent_task_run.attempt_no,
        "terminal_payload" => { "output" => unsafe_output },
      },
      occurred_at: Time.current
    )

    summary = agent_task_run.reload.recent_progress_summary
    entry = agent_task_run.agent_task_progress_entries.order(:sequence).last

    assert summary.present?
    assert_operator summary.length, :<=, SupervisionStateFields::HUMAN_SUMMARY_MAX_LENGTH
    refute_match(/provider_round_|runtime\./, summary)
    assert_equal summary, entry.summary
  end

  test "execution_complete on a child subagent task records terminal progress without linking the owner session" do
    context = build_agent_control_context!
    child_scenario = spawn_child_subagent_execution!(context:)
    mailbox_item = child_scenario.fetch(:mailbox_item)
    agent_task_run = child_scenario.fetch(:agent_task_run)
    subagent_connection = child_scenario.fetch(:subagent_connection)

    report_execution_started!(
      agent_definition_version: context.fetch(:agent_definition_version),
      mailbox_item: mailbox_item,
      agent_task_run: agent_task_run
    )

    AgentControl::HandleExecutionReport.call(
      agent_definition_version: context[:agent_definition_version],
      method_id: "execution_complete",
      payload: {
        "mailbox_item_id" => mailbox_item.public_id,
        "agent_task_run_id" => agent_task_run.public_id,
        "logical_work_id" => agent_task_run.logical_work_id,
        "attempt_no" => agent_task_run.attempt_no,
        "terminal_payload" => { "output" => "Subagent work finished cleanly" },
      },
      occurred_at: Time.current
    )

    entry = agent_task_run.reload.agent_task_progress_entries.order(:sequence).last

    assert_equal "execution_completed", entry.entry_kind
    assert_nil entry.subagent_connection
    assert_equal "completed", subagent_connection.reload.observed_status
    assert_equal "completed", subagent_connection.supervision_state
  end

  private

  def spawn_child_subagent_execution!(context:)
    promote_subagent_runtime_context!(context)

    result = SubagentConnections::Spawn.call(
      conversation: context.fetch(:conversation),
      origin_turn: context.fetch(:turn),
      content: "Investigate the failing branch",
      scope: "conversation",
      profile_key: "researcher"
    )
    agent_task_run = AgentTaskRun.find_by!(public_id: result.fetch("agent_task_run_id"))

    {
      agent_task_run: agent_task_run,
      mailbox_item: AgentControlMailboxItem.find_by!(
        agent_task_run: agent_task_run,
        item_type: "execution_assignment"
      ),
      subagent_connection: SubagentConnection.find_by!(public_id: result.fetch("subagent_connection_id")),
    }
  end

  def assert_terminal_execution_report!(method_id:, lifecycle_state:, entry_kind:, projected_overall_state:, projected_board_lane:, terminal_payload:)
    context = build_agent_control_context!
    scenario = MailboxScenarioBuilder.new(self).execution_assignment!(context: context)
    mailbox_item = scenario.fetch(:mailbox_item)
    agent_task_run = scenario.fetch(:agent_task_run)

    report_execution_started!(
      agent_definition_version: context.fetch(:agent_definition_version),
      mailbox_item: mailbox_item,
      agent_task_run: agent_task_run
    )

    AgentControl::HandleExecutionReport.call(
      agent_definition_version: context[:agent_definition_version],
      method_id: method_id,
      payload: {
        "mailbox_item_id" => mailbox_item.public_id,
        "agent_task_run_id" => agent_task_run.public_id,
        "logical_work_id" => agent_task_run.logical_work_id,
        "attempt_no" => agent_task_run.attempt_no,
        "terminal_payload" => terminal_payload,
      },
      occurred_at: Time.current
    )

    agent_task_run.reload
    entry = agent_task_run.agent_task_progress_entries.order(:sequence).last

    assert_equal lifecycle_state, agent_task_run.lifecycle_state
    assert_equal entry_kind, entry.entry_kind
    assert entry.summary.present?
    refute_match(/provider_round_|runtime\.|subagent_barrier/, entry.summary)
    supervision_state = context[:conversation].reload.conversation_supervision_state
    assert_equal projected_overall_state, supervision_state.overall_state
    assert_equal projected_board_lane, supervision_state.board_lane
    assert_equal lifecycle_state, supervision_state.last_terminal_state
  end
end
