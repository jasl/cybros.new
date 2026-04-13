module ConversationSupervision
  class LoadLatestActiveTaskRuns
    ACTIVE_TASK_LIFECYCLE_STATES = %w[queued running].freeze
    TODO_PLAN_INCLUDES = [
      :conversation,
      :turn,
      :agent_task_run,
      { turn_todo_plan_items: :delegated_subagent_connection },
    ].freeze

    def self.call(...)
      new(...).call
    end

    def initialize(conversation_ids:, include_progress_entries: false)
      @conversation_ids = Array(conversation_ids).compact.uniq
      @include_progress_entries = include_progress_entries
    end

    def call
      return {} if @conversation_ids.empty?

      AgentTaskRun
        .where(conversation_id: @conversation_ids, lifecycle_state: ACTIVE_TASK_LIFECYCLE_STATES)
        .includes(*includes)
        .order(:conversation_id, created_at: :desc, id: :desc)
        .each_with_object({}) do |agent_task_run, runs_by_conversation_id|
          runs_by_conversation_id[agent_task_run.conversation_id] ||= agent_task_run
        end
    end

    private

    def includes
      includes = [{ turn_todo_plan: TODO_PLAN_INCLUDES }]
      includes.unshift(:agent_task_progress_entries) if @include_progress_entries
      includes
    end
  end
end
