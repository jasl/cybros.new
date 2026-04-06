require "test_helper"

class AgentControl::HandleExecutionReportTurnTodoPlanTest < ActiveSupport::TestCase
  test "execution_progress applies turn_todo_plan_update through the dedicated plan path" do
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
      deployment: context.fetch(:deployment),
      method_id: "execution_progress",
      payload: {
        "mailbox_item_id" => mailbox_item.public_id,
        "agent_task_run_id" => agent_task_run.public_id,
        "logical_work_id" => agent_task_run.logical_work_id,
        "attempt_no" => agent_task_run.attempt_no,
        "progress_payload" => {
          "turn_todo_plan_update" => {
            "goal_summary" => "Route plan updates through the new domain",
            "current_item_key" => "wire-supervision",
            "items" => [
              {
                "item_key" => "define-domain",
                "title" => "Define the new plan model",
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
        },
      },
      occurred_at: Time.current
    )

    plan = agent_task_run.reload.turn_todo_plan
    supervision_state = context[:conversation].reload.conversation_supervision_state

    assert_equal "wire-supervision", plan.current_item_key
    assert_equal "Route plan updates through the new domain", plan.goal_summary
    assert_equal %w[define-domain wire-supervision], plan.turn_todo_plan_items.order(:position).pluck(:item_key)
    assert_equal "running", supervision_state.overall_state
    assert_equal "agent_task_run", supervision_state.current_owner_kind
    assert_equal agent_task_run.public_id, supervision_state.current_owner_public_id
  end
end
