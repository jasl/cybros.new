require "test_helper"

module TurnTodoPlans
  class BuildViewTest < ActiveSupport::TestCase
    test "builds full and compact plan views from the current plan head" do
      context = build_agent_control_context!
      agent_task_run = create_agent_task_run!(
        workflow_node: context[:workflow_node],
        lifecycle_state: "running",
        started_at: 2.minutes.ago,
        supervision_state: "running",
        last_progress_at: 1.minute.ago,
        supervision_payload: {}
      )
      plan = TurnTodoPlans::ApplyUpdate.call(
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

      view = TurnTodoPlans::BuildView.call(turn_todo_plan: plan)
      compact_view = TurnTodoPlans::BuildCompactView.call(turn_todo_plan: plan)

      assert_equal plan.public_id, view.fetch("turn_todo_plan_id")
      assert_equal agent_task_run.public_id, view.fetch("agent_task_run_id")
      assert_equal "wire-supervision", view.fetch("current_item_key")
      assert_equal "Wire plan views into supervision", view.dig("current_item", "title")
      assert_equal %w[define-domain wire-supervision], view.fetch("items").map { |item| item.fetch("item_key") }

      assert_equal plan.public_id, compact_view.fetch("turn_todo_plan_id")
      assert_equal "Replace AgentTaskPlanItem with TurnTodoPlan", compact_view.fetch("goal_summary")
      assert_equal "wire-supervision", compact_view.fetch("current_item_key")
      assert_equal "Wire plan views into supervision", compact_view.fetch("current_item_title")
      assert_equal 1, compact_view.fetch("active_item_count")
      assert_equal 1, compact_view.fetch("completed_item_count")
    end
  end
end
