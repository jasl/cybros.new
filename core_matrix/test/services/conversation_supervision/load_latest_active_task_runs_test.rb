require "test_helper"

class ConversationSupervision::LoadLatestActiveTaskRunsTest < ActiveSupport::TestCase
  include ConversationSupervisionFixtureBuilder

  test "loads the latest active task run for each conversation without extra todo-plan view queries" do
    fixture = prepare_conversation_supervision_context_with_turn_todo_plan!

    runs_by_conversation_id = ConversationSupervision::LoadLatestActiveTaskRuns.call(
      conversation_ids: [
        fixture.fetch(:conversation).id,
        fixture.fetch(:subagent_connection).conversation_id,
      ]
    )

    assert_equal fixture.fetch(:agent_task_run).id, runs_by_conversation_id.fetch(fixture.fetch(:conversation).id).id
    assert_equal fixture.fetch(:child_agent_task_run).id,
      runs_by_conversation_id.fetch(fixture.fetch(:subagent_connection).conversation_id).id

    queries = capture_sql_queries do
      runs_by_conversation_id.values.each do |agent_task_run|
        TurnTodoPlans::BuildView.call(turn_todo_plan: agent_task_run.turn_todo_plan)
      end
    end

    assert queries.none? { |sql| sql.match?(/FROM "turn_todo_plans"|FROM "turn_todo_plan_items"|FROM "agent_task_runs"|FROM "conversations"|FROM "turns"/) },
      "Expected preloaded task runs to build plan views without extra SQL, got:\n#{queries.join("\n")}"
  end
end
