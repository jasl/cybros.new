require "test_helper"

module TurnTodoPlans
  class ApplyUpdateTest < ActiveSupport::TestCase
    test "replaces the mutable plan head from a full snapshot" do
      fixture = build_turn_todo_plan_owner_fixture!

      assert_nil fixture.fetch(:agent_task_run).turn_todo_plan

      TurnTodoPlans::ApplyUpdate.call(
        agent_task_run: fixture.fetch(:agent_task_run),
        payload: {
          "goal_summary" => "Seed the initial plan",
          "current_item_key" => "old-item",
          "items" => [
            { "item_key" => "old-item", "title" => "Old item", "status" => "in_progress", "position" => 0, "kind" => "implementation" },
          ],
        },
        occurred_at: 2.minutes.ago
      )

      TurnTodoPlans::ApplyUpdate.call(
        agent_task_run: fixture.fetch(:agent_task_run),
        payload: {
          "goal_summary" => "Replace old plan pathways",
          "current_item_key" => "remove-stale-path",
          "items" => [
            { "item_key" => "define-domain", "title" => "Define new plan model", "status" => "completed", "position" => 0, "kind" => "implementation" },
            { "item_key" => "remove-stale-path", "title" => "Remove AgentTaskPlanItem", "status" => "in_progress", "position" => 1, "kind" => "implementation" },
          ],
        },
        occurred_at: Time.current
      )

      plan = fixture.fetch(:agent_task_run).reload.turn_todo_plan

      assert_equal "Replace old plan pathways", plan.goal_summary
      assert_equal "remove-stale-path", plan.current_item_key
      assert_equal %w[define-domain remove-stale-path], plan.turn_todo_plan_items.order(:position).pluck(:item_key)
      assert_equal 2, plan.turn_todo_plan_items.count
      assert_equal 1, plan.counts_payload.fetch("completed")
      assert_equal 1, plan.counts_payload.fetch("in_progress")
    end

    private

    def build_turn_todo_plan_owner_fixture!
      context = build_agent_control_context!
      agent_task_run = create_agent_task_run!(
        workflow_node: context.fetch(:workflow_node),
        lifecycle_state: "running",
        started_at: Time.current,
        supervision_state: "running",
        focus_kind: "planning",
        last_progress_at: 5.minutes.ago,
        supervision_payload: {}
      )

      {
        context: context,
        agent_task_run: agent_task_run,
      }
    end
  end
end
