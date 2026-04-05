require "test_helper"

class AgentControl::HandleExecutionReportTest < ActiveSupport::TestCase
  test "maps stale heartbeat timeouts to stale reports without mutating execution progress" do
    context = build_agent_control_context!
    scenario = MailboxScenarioBuilder.new(self).execution_assignment!(context: context)
    mailbox_item = scenario.fetch(:mailbox_item)
    agent_task_run = scenario.fetch(:agent_task_run)
    started_at = Time.zone.parse("2026-03-29 22:00:00 UTC")

    travel_to(started_at) do
      agent_task_run.update!(
        lifecycle_state: "running",
        holder_agent_session: context[:agent_session],
        started_at: started_at
      )
      Leases::Acquire.call(
        leased_resource: agent_task_run,
        holder_key: context[:deployment].public_id,
        heartbeat_timeout_seconds: 30
      )
      mailbox_item.update!(
        status: "acked",
        leased_to_agent_session: context[:agent_session],
        leased_at: started_at,
        lease_expires_at: started_at + mailbox_item.lease_timeout_seconds.seconds,
        acked_at: started_at
      )
    end

    assert_raises(AgentControl::Report::StaleReportError) do
      AgentControl::HandleExecutionReport.call(
        deployment: context[:deployment],
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
      deployment: context.fetch(:deployment),
      mailbox_item: mailbox_item,
      agent_task_run: agent_task_run
    )

    AgentControl::HandleExecutionReport.call(
      deployment: context[:deployment],
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
            "plan_items" => [
              {
                "item_key" => "projection",
                "title" => "Add conversation supervision state",
                "status" => "completed",
                "position" => 0
              },
              {
                "item_key" => "renderer",
                "title" => "Rebuild sidechat renderer",
                "status" => "in_progress",
                "position" => 1
              }
            ]
          }
        }
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
    assert_equal %w[projection renderer], agent_task_run.agent_task_plan_items.order(:position).pluck(:item_key)
    assert_equal "Finished reviewing the old models", agent_task_run.agent_task_progress_entries.order(:sequence).last.summary

    supervision_state = context[:conversation].reload.conversation_supervision_state
    assert_equal "running", supervision_state.overall_state
    assert_equal "agent_task_run", supervision_state.current_owner_kind
    assert_equal agent_task_run.public_id, supervision_state.current_owner_public_id
    assert_equal "Adding the canonical supervision aggregates", supervision_state.current_focus_summary
  end

  test "execution_complete appends a semantic completion entry" do
    assert_terminal_execution_report!(
      method_id: "execution_complete",
      lifecycle_state: "completed",
      entry_kind: "execution_completed",
      terminal_payload: { "output" => "Shipped the projector" }
    )
  end

  test "execution_fail appends a semantic failure entry" do
    assert_terminal_execution_report!(
      method_id: "execution_fail",
      lifecycle_state: "failed",
      entry_kind: "execution_failed",
      terminal_payload: { "last_error_summary" => "Provider timed out while saving the projection" }
    )
  end

  test "execution_interrupted appends a semantic interruption entry" do
    assert_terminal_execution_report!(
      method_id: "execution_interrupted",
      lifecycle_state: "interrupted",
      entry_kind: "execution_interrupted",
      terminal_payload: {}
    )
  end

  private

  def assert_terminal_execution_report!(method_id:, lifecycle_state:, entry_kind:, terminal_payload:)
    context = build_agent_control_context!
    scenario = MailboxScenarioBuilder.new(self).execution_assignment!(context: context)
    mailbox_item = scenario.fetch(:mailbox_item)
    agent_task_run = scenario.fetch(:agent_task_run)

    report_execution_started!(
      deployment: context.fetch(:deployment),
      mailbox_item: mailbox_item,
      agent_task_run: agent_task_run
    )

    AgentControl::HandleExecutionReport.call(
      deployment: context[:deployment],
      method_id: method_id,
      payload: {
        "mailbox_item_id" => mailbox_item.public_id,
        "agent_task_run_id" => agent_task_run.public_id,
        "logical_work_id" => agent_task_run.logical_work_id,
        "attempt_no" => agent_task_run.attempt_no,
        "terminal_payload" => terminal_payload
      },
      occurred_at: Time.current
    )

    agent_task_run.reload
    entry = agent_task_run.agent_task_progress_entries.order(:sequence).last

    assert_equal lifecycle_state, agent_task_run.lifecycle_state
    assert_equal entry_kind, entry.entry_kind
    assert entry.summary.present?
    refute_match(/provider_round_|runtime\.|subagent_barrier/, entry.summary)
    assert_equal lifecycle_state, context[:conversation].reload.conversation_supervision_state.overall_state
  end
end
