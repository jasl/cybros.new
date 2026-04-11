module SubagentConnections
  class Wait
    TERMINAL_OBSERVED_STATUSES = %w[completed failed interrupted].freeze

    def self.call(...)
      new(...).call
    end

    def initialize(subagent_connection:, timeout_seconds:, poll_interval_seconds: 0.1)
      @subagent_connection = subagent_connection
      @timeout_seconds = timeout_seconds.to_f
      @poll_interval_seconds = poll_interval_seconds.to_f
    end

    def call
      deadline_at = Time.current + @timeout_seconds

      loop do
        session = @subagent_connection.reload
        return serialize(session, timed_out: false) if terminal?(session)
        return serialize(session, timed_out: true) if Time.current >= deadline_at

        sleep @poll_interval_seconds
      end
    end

    private

    def terminal?(session)
      session.terminal_close? || TERMINAL_OBSERVED_STATUSES.include?(session.observed_status)
    end

    def serialize(session, timed_out:)
      {
        "subagent_connection_id" => session.public_id,
        "timed_out" => timed_out,
        "derived_close_status" => session.derived_close_status,
        "observed_status" => session.observed_status,
        "close_state" => session.close_state,
        "supervision_state" => session.supervision_state,
        "current_focus_summary" => session.current_focus_summary,
        "recent_progress_summary" => session.recent_progress_summary,
        "waiting_summary" => session.waiting_summary,
        "blocked_summary" => session.blocked_summary,
        "next_step_hint" => session.next_step_hint,
        "result_envelope" => result_envelope(session, timed_out: timed_out),
      }
    end

    def result_envelope(session, timed_out:)
      return if timed_out

      task_run = latest_child_task_run(session)
      return if task_run.blank?

      terminal_payload = task_run.terminal_payload.deep_stringify_keys

      {
        "conversation_id" => session.conversation.public_id,
        "turn_id" => task_run.turn.public_id,
        "workflow_run_id" => task_run.workflow_run.public_id,
        "agent_task_run_id" => task_run.public_id,
        "lifecycle_state" => task_run.lifecycle_state,
        "request_summary" => task_run.request_summary,
        "result_summary" => terminal_payload["output"] || terminal_payload["last_error_summary"],
        "output" => terminal_payload["output"],
        "last_error_summary" => terminal_payload["last_error_summary"],
        "failure_kind" => terminal_payload["failure_kind"],
        "retryable" => terminal_payload["retryable"],
      }.compact
    end

    def latest_child_task_run(session)
      session.agent_task_runs
        .where(lifecycle_state: %w[completed failed interrupted canceled])
        .order(finished_at: :desc, created_at: :desc)
        .first
    end
  end
end
