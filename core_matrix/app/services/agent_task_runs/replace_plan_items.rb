module AgentTaskRuns
  class ReplacePlanItems
    def self.call(...)
      new(...).call
    end

    def initialize(agent_task_run:, plan_items:, occurred_at: Time.current)
      @agent_task_run = agent_task_run
      @plan_items = Array(plan_items).map { |entry| entry.deep_stringify_keys }
      @occurred_at = occurred_at
    end

    def call
      ApplicationRecord.transaction do
        @agent_task_run.with_lock do
          @agent_task_run.reload
          @agent_task_run.agent_task_plan_items.delete_all

          items_by_key = {}
          @plan_items.each_with_index do |entry, index|
            item = @agent_task_run.agent_task_plan_items.create!(
              installation: @agent_task_run.installation,
              delegated_subagent_session: delegated_subagent_session_for(entry["delegated_subagent_session_public_id"]),
              item_key: entry.fetch("item_key"),
              title: entry.fetch("title"),
              status: entry.fetch("status", "pending"),
              position: entry.fetch("position", index),
              details_payload: entry.fetch("details_payload", {}),
              last_status_changed_at: @occurred_at
            )
            items_by_key[item.item_key] = item
          end

          @plan_items.each do |entry|
            next if entry["parent_item_key"].blank?

            item = items_by_key.fetch(entry.fetch("item_key"))
            parent_item = items_by_key[entry.fetch("parent_item_key")] ||
              raise(ActiveRecord::RecordNotFound, "Couldn't find parent plan item #{entry.fetch("parent_item_key")}")
            item.update!(parent_plan_item: parent_item)
          end

          in_progress_item = @agent_task_run.agent_task_plan_items.find_by(status: "in_progress")

          @agent_task_run.update!(
            current_focus_summary: in_progress_item&.title,
            next_step_hint: next_pending_title_after(in_progress_item),
            last_progress_at: @occurred_at,
            supervision_sequence: @agent_task_run.supervision_sequence.to_i + 1
          )
        end
      end
    end

    private

    def delegated_subagent_session_for(public_id)
      return if public_id.blank?

      @agent_task_run.conversation.owned_subagent_sessions.find_by!(public_id: public_id)
    end

    def next_pending_title_after(in_progress_item)
      scope = @agent_task_run.agent_task_plan_items.where(status: "pending").order(:position)
      scope = scope.where("position > ?", in_progress_item.position) if in_progress_item.present?
      scope.pick(:title) || @agent_task_run.agent_task_plan_items.where(status: "pending").order(:position).pick(:title)
    end
  end
end
