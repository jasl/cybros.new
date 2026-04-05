module ConversationSupervision
  class ClassifyBoardLane
    def self.call(...)
      new(...).call
    end

    def initialize(overall_state:, active_subagent_count:, retry_due_at:)
      @overall_state = overall_state.to_s
      @active_subagent_count = active_subagent_count.to_i
      @retry_due_at = retry_due_at
    end

    def call
      case @overall_state
      when "idle" then "idle"
      when "queued" then "queued"
      when "running" then "active"
      when "waiting" then @active_subagent_count.positive? ? "handoff" : "waiting"
      when "blocked" then "blocked"
      when "completed", "interrupted", "canceled" then "done"
      when "failed" then "failed"
      else
        "queued"
      end
    end
  end
end
