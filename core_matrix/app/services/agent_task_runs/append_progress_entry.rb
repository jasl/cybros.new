module AgentTaskRuns
  class AppendProgressEntry
    def self.call(...)
      new(...).call
    end

    def initialize(agent_task_run:, entry_kind:, summary:, details_payload: {}, occurred_at: Time.current, subagent_session: nil)
      @agent_task_run = agent_task_run
      @entry_kind = entry_kind
      @summary = summary
      @details_payload = details_payload.deep_stringify_keys
      @occurred_at = occurred_at
      @subagent_session = subagent_session
    end

    def call
      entry = nil

      ApplicationRecord.transaction do
        @agent_task_run.with_lock do
          @agent_task_run.reload

          next_sequence = @agent_task_run.agent_task_progress_entries.maximum(:sequence).to_i + 1
          entry = @agent_task_run.agent_task_progress_entries.create!(
            installation: @agent_task_run.installation,
            subagent_session: @subagent_session,
            sequence: next_sequence,
            entry_kind: @entry_kind,
            summary: @summary,
            details_payload: @details_payload,
            occurred_at: @occurred_at
          )

          @agent_task_run.update!(
            recent_progress_summary: entry.summary,
            last_progress_at: @occurred_at,
            supervision_sequence: @agent_task_run.supervision_sequence.to_i + 1
          )
        end
      end

      entry
    end
  end
end
