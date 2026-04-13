module ConversationSupervision
  class BuildCurrentTurnTodo
    ACTIVE_TASK_LIFECYCLE_STATES = %w[queued running].freeze

    def self.call(...)
      new(...).call
    end

    def initialize(conversation:, active_agent_task_run: nil, workflow_run: nil)
      @conversation = conversation
      @active_agent_task_run = active_agent_task_run if active_agent_task_run.present?
      @workflow_run = workflow_run if workflow_run.present?
    end

    def call
      return empty_projection if active_agent_task_run&.turn_todo_plan.blank?

      {
        "plan_view" => TurnTodoPlans::BuildView.call(turn_todo_plan: active_agent_task_run.turn_todo_plan),
        "plan_summary" => TurnTodoPlans::BuildCompactView.call(turn_todo_plan: active_agent_task_run.turn_todo_plan),
        "synthetic_turn_feed" => [],
      }
    end

    private

    def active_agent_task_run
      return @active_agent_task_run if instance_variable_defined?(:@active_agent_task_run)

      @active_agent_task_run = AgentTaskRun
        .where(conversation: @conversation, lifecycle_state: ACTIVE_TASK_LIFECYCLE_STATES)
        .includes(
          turn_todo_plan: [
            :conversation,
            :turn,
            :agent_task_run,
            { turn_todo_plan_items: :delegated_subagent_connection },
          ]
        )
        .order(created_at: :desc)
        .first
    end

    def empty_projection
      {
        "plan_view" => nil,
        "plan_summary" => nil,
        "synthetic_turn_feed" => [],
      }
    end
  end
end
