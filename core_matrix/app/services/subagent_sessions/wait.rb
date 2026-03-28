module SubagentSessions
  class Wait
    TERMINAL_LAST_KNOWN_STATUSES = %w[completed failed interrupted].freeze

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
      session.lifecycle_closed? ||
        session.close_failed? ||
        TERMINAL_LAST_KNOWN_STATUSES.include?(session.last_known_status)
    end

    def serialize(session, timed_out:)
      {
        "subagent_session_id" => session.public_id,
        "timed_out" => timed_out,
        "lifecycle_state" => session.lifecycle_state,
        "last_known_status" => session.last_known_status,
        "close_state" => session.close_state,
      }
    end
  end
end
