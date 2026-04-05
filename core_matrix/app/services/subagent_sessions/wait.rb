module SubagentSessions
  class Wait
    TERMINAL_OBSERVED_STATUSES = %w[completed failed interrupted].freeze

    def self.call(...)
      new(...).call
    end

    def initialize(subagent_session:, timeout_seconds:, poll_interval_seconds: 0.1)
      @subagent_session = subagent_session
      @timeout_seconds = timeout_seconds.to_f
      @poll_interval_seconds = poll_interval_seconds.to_f
    end

    def call
      deadline_at = Time.current + @timeout_seconds

      loop do
        session = @subagent_session.reload
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
        "subagent_session_id" => session.public_id,
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
      }
    end
  end
end
