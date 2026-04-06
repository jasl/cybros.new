module TurnTodoPlans
  class ApplyUpdate
    def self.call(...)
      new(...).call
    end

    def initialize(agent_task_run:, payload:, occurred_at: Time.current)
      @agent_task_run = agent_task_run
      @payload = normalize_payload(payload)
      @occurred_at = occurred_at
    end

    def call
      ApplicationRecord.transaction do
        @agent_task_run.with_lock do
          @agent_task_run.reload
          previous_plan = TurnTodoPlans::BuildView.call(turn_todo_plan: @agent_task_run.turn_todo_plan)
          plan = upsert_plan_head!
          replace_plan_items!(plan)
          plan.update!(counts_payload: TurnTodoPlans::BuildCounts.call(items: plan.turn_todo_plan_items))
          append_feed_entries!(previous_plan:, current_plan: TurnTodoPlans::BuildView.call(turn_todo_plan: plan))
          plan
        end
      end
    end

    private

    def normalize_payload(payload)
      payload = payload.to_h.deep_stringify_keys
      items = payload["items"]

      raise ArgumentError, "turn_todo_plan_update payload must include an items array" unless items.is_a?(Array)

      payload.merge("items" => items.map { |entry| entry.to_h.deep_stringify_keys })
    end

    def upsert_plan_head!
      plan = @agent_task_run.turn_todo_plan || @agent_task_run.build_turn_todo_plan
      plan.assign_attributes(
        installation: @agent_task_run.installation,
        conversation: @agent_task_run.conversation,
        turn: @agent_task_run.turn,
        status: "active",
        goal_summary: @payload.fetch("goal_summary"),
        current_item_key: @payload["current_item_key"],
        counts_payload: plan.counts_payload.presence || {},
        closed_at: nil
      )
      plan.save!
      plan
    end

    def replace_plan_items!(plan)
      plan.turn_todo_plan_items.delete_all

      @payload.fetch("items").each_with_index do |entry, index|
        plan.turn_todo_plan_items.create!(
          installation: plan.installation,
          delegated_subagent_session: delegated_subagent_session_for(entry["delegated_subagent_session_public_id"]),
          item_key: entry.fetch("item_key"),
          title: entry.fetch("title"),
          status: entry.fetch("status", "pending"),
          position: entry.fetch("position", index),
          kind: entry.fetch("kind"),
          details_payload: entry.fetch("details_payload", {}),
          depends_on_item_keys: entry.fetch("depends_on_item_keys", []),
          last_status_changed_at: @occurred_at
        )
      end
    end

    def delegated_subagent_session_for(public_id)
      return if public_id.blank?

      @agent_task_run.conversation.owned_subagent_sessions.find_by!(public_id: public_id)
    end

    def append_feed_entries!(previous_plan:, current_plan:)
      changeset = TurnTodoPlans::BuildFeedChangeset.call(
        previous_plan: previous_plan,
        current_plan: current_plan,
        occurred_at: @occurred_at
      )
      return if changeset.empty?

      ConversationSupervision::AppendFeedEntries.call(
        conversation: @agent_task_run.conversation,
        changeset: changeset,
        occurred_at: @occurred_at
      )
    end
  end
end
