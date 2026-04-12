require "test_helper"

class TurnTodoPlanCleanupContractTest < ActionDispatch::IntegrationTest
  test "rejects legacy plan updates and old feed semantics" do
    context = build_agent_control_context!
    scenario = MailboxScenarioBuilder.new(self).execution_assignment!(context: context)
    mailbox_item = scenario.fetch(:mailbox_item)
    agent_task_run = scenario.fetch(:agent_task_run)

    report_execution_started!(
      agent_definition_version: context.fetch(:agent_definition_version),
      mailbox_item: mailbox_item,
      agent_task_run: agent_task_run
    )

    assert_raises(ArgumentError) do
      AgentControl::HandleExecutionReport.call(
        agent_definition_version: context.fetch(:agent_definition_version),
        method_id: "execution_progress",
        payload: {
          "mailbox_item_id" => mailbox_item.public_id,
          "agent_task_run_id" => agent_task_run.public_id,
          "logical_work_id" => agent_task_run.logical_work_id,
          "attempt_no" => agent_task_run.attempt_no,
          "progress_payload" => {
            "supervision_update" => {
              "plan_items" => [
                {
                  "item_key" => "legacy",
                  "title" => "Legacy path",
                  "status" => "pending",
                  "position" => 0,
                },
              ],
            },
          },
        },
        occurred_at: Time.current
      )
    end

    AgentControl::HandleExecutionReport.call(
      agent_definition_version: context.fetch(:agent_definition_version),
      method_id: "execution_progress",
      payload: {
        "mailbox_item_id" => mailbox_item.public_id,
        "agent_task_run_id" => agent_task_run.public_id,
        "logical_work_id" => agent_task_run.logical_work_id,
        "attempt_no" => agent_task_run.attempt_no,
        "progress_payload" => {
          "turn_todo_plan_update" => {
            "goal_summary" => "Remove the legacy supervision plan path",
            "current_item_key" => "cleanup",
            "items" => [
              {
                "item_key" => "cleanup",
                "title" => "Clean up the legacy plan path",
                "status" => "in_progress",
                "position" => 0,
                "kind" => "implementation",
              },
            ],
          },
        },
      },
      occurred_at: Time.current
    )

    state = context.fetch(:conversation).reload.conversation_supervision_state
    feed_kinds = ConversationSupervision::BuildActivityFeed.call(conversation: context.fetch(:conversation)).map { |entry| entry.fetch("event_kind") }
    purge_plan = Conversations::PurgePlan.new(conversation: context.fetch(:conversation).reload)

    refute state.status_payload.key?("active_plan_items")
    assert_includes feed_kinds, "turn_todo_item_started"
    refute_includes feed_kinds, "progress_recorded"
    assert purge_plan.remaining_owned_rows?

    purge_plan.execute!

    assert_not purge_plan.remaining_owned_rows?
  end
end
