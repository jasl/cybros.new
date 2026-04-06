module TurnTodoPlans
  class BuildView
    def self.call(...)
      new(...).call
    end

    def initialize(turn_todo_plan:)
      @turn_todo_plan = turn_todo_plan
    end

    def call
      return if @turn_todo_plan.blank?

      items = ordered_items
      current_item = items.find { |item| item.item_key == @turn_todo_plan.current_item_key }

      {
        "turn_todo_plan_id" => @turn_todo_plan.public_id,
        "agent_task_run_id" => @turn_todo_plan.agent_task_run.public_id,
        "conversation_id" => @turn_todo_plan.conversation.public_id,
        "turn_id" => @turn_todo_plan.turn.public_id,
        "status" => @turn_todo_plan.status,
        "goal_summary" => @turn_todo_plan.goal_summary,
        "current_item_key" => @turn_todo_plan.current_item_key,
        "current_item" => serialize_item(current_item),
        "counts" => normalized_counts(items: items),
        "items" => items.map { |item| serialize_item(item) },
      }.compact
    end

    private

    def ordered_items
      @ordered_items ||= @turn_todo_plan.turn_todo_plan_items.sort_by(&:position)
    end

    def normalized_counts(items:)
      counts = @turn_todo_plan.counts_payload.presence
      return counts.deep_stringify_keys if counts.present?

      TurnTodoPlans::BuildCounts.call(items: items).deep_stringify_keys
    end

    def serialize_item(item)
      return if item.blank?

      {
        "turn_todo_plan_item_id" => item.public_id,
        "item_key" => item.item_key,
        "title" => item.title,
        "status" => item.status,
        "position" => item.position,
        "kind" => item.kind,
        "details_payload" => item.details_payload,
        "depends_on_item_keys" => item.depends_on_item_keys,
        "delegated_subagent_session_id" => item.delegated_subagent_session&.public_id,
      }.compact
    end
  end
end
