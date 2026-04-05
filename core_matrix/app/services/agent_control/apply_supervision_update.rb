module AgentControl
  class ApplySupervisionUpdate
    ALLOWED_FIELDS = %w[
      supervision_state
      focus_kind
      request_summary
      current_focus_summary
      recent_progress_summary
      waiting_summary
      blocked_summary
      next_step_hint
      plan_items
    ].freeze

    def self.call(...)
      new(...).call
    end

    def initialize(agent_task_run:, payload:, occurred_at: Time.current)
      @agent_task_run = agent_task_run
      @payload = payload.deep_stringify_keys
      @occurred_at = occurred_at
    end

    def call
      supervision_update = @payload.fetch("supervision_update").deep_stringify_keys.slice(*ALLOWED_FIELDS)
      validate_supervision_update!(supervision_update)

      AgentTaskRuns::ReplacePlanItems.call(
        agent_task_run: @agent_task_run,
        plan_items: supervision_update.fetch("plan_items"),
        occurred_at: @occurred_at
      ) if supervision_update.key?("plan_items")
      AgentTaskRuns::AppendProgressEntry.call(
        agent_task_run: @agent_task_run,
        subagent_session: @agent_task_run.subagent_session,
        entry_kind: "progress_recorded",
        summary: supervision_update.fetch("recent_progress_summary"),
        details_payload: {},
        occurred_at: @occurred_at
      ) if supervision_update["recent_progress_summary"].present?
      @agent_task_run.reload.update!(task_attributes_from(supervision_update))
      sync_subagent_session!(supervision_update)

      refresh_related_conversations!
    end

    private

    def validate_supervision_update!(supervision_update)
      summary_fields = %w[
        request_summary
        current_focus_summary
        recent_progress_summary
        waiting_summary
        blocked_summary
        next_step_hint
      ]
      summary_fields.each do |field_name|
        value = supervision_update[field_name]
        next if value.blank?
        next unless AgentTaskProgressEntry::INTERNAL_RUNTIME_TOKEN_PATTERN.match?(value)

        raise ArgumentError, "#{field_name} must not expose internal runtime tokens"
      end
    end

    def task_attributes_from(supervision_update)
      supervision_update.slice(
        "supervision_state",
        "focus_kind",
        "request_summary",
        "current_focus_summary",
        "recent_progress_summary",
        "waiting_summary",
        "blocked_summary",
        "next_step_hint"
      ).merge(
        "last_progress_at" => @occurred_at
      )
    end

    def sync_subagent_session!(supervision_update)
      session = @agent_task_run.subagent_session
      return if session.blank?

      session.update!(
        supervision_update.slice(
          "supervision_state",
          "focus_kind",
          "request_summary",
          "current_focus_summary",
          "recent_progress_summary",
          "waiting_summary",
          "blocked_summary",
          "next_step_hint"
        ).merge(
          "observed_status" => observed_status_for(supervision_update["supervision_state"]),
          "last_progress_at" => @occurred_at
        )
      )
    end

    def observed_status_for(supervision_state)
      case supervision_state
      when "queued" then "idle"
      when "waiting", "blocked" then "waiting"
      when "completed" then "completed"
      when "failed" then "failed"
      when "interrupted", "canceled" then "interrupted"
      else "running"
      end
    end

    def refresh_related_conversations!
      related_conversations.each do |conversation|
        Conversations::UpdateSupervisionState.call(
          conversation: conversation,
          occurred_at: @occurred_at
        )
      end
    end

    def related_conversations
      [@agent_task_run.conversation, @agent_task_run.subagent_session&.owner_conversation].compact.uniq
    end
  end
end
