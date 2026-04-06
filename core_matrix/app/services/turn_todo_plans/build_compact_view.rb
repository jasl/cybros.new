module TurnTodoPlans
  class BuildCompactView
    ACTIVE_ITEM_STATUSES = %w[pending in_progress blocked failed].freeze

    def self.call(...)
      new(...).call
    end

    def initialize(turn_todo_plan:)
      @turn_todo_plan = turn_todo_plan
    end

    def call
      view = TurnTodoPlans::BuildView.call(turn_todo_plan: @turn_todo_plan)
      return if view.blank?

      counts = view.fetch("counts", {})
      {
        "turn_todo_plan_id" => view.fetch("turn_todo_plan_id"),
        "agent_task_run_id" => view.fetch("agent_task_run_id"),
        "conversation_id" => view.fetch("conversation_id"),
        "turn_id" => view.fetch("turn_id"),
        "status" => view.fetch("status"),
        "goal_summary" => view.fetch("goal_summary"),
        "current_item_key" => view["current_item_key"],
        "current_item_title" => view.dig("current_item", "title"),
        "current_item_status" => view.dig("current_item", "status"),
        "active_item_count" => ACTIVE_ITEM_STATUSES.sum { |status| counts.fetch(status, 0).to_i },
        "completed_item_count" => counts.fetch("completed", 0).to_i,
        "total_item_count" => counts.values.sum(&:to_i),
      }.compact
    end
  end
end
