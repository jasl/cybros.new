module Turns
  class RecoverWorkflowBootstrapBacklog
    DEFAULT_STALE_WINDOW = 5.minutes

    def self.call(...)
      new(...).call
    end

    def initialize(stale_before: nil)
      @stale_before = stale_before || DEFAULT_STALE_WINDOW.ago
    end

    def call
      pending_turns.find_each do |turn|
        Turns::MaterializeAndDispatchJob.perform_later(turn.public_id)
      end

      stale_materializing_turns.find_each do |turn|
        Turns::MaterializeAndDispatchJob.perform_later(turn.public_id)
      end
    end

    private

    def pending_turns
      Turn.where(workflow_bootstrap_state: "pending", workflow_bootstrap_started_at: nil)
    end

    def stale_materializing_turns
      Turn.where(workflow_bootstrap_state: "materializing")
        .where("workflow_bootstrap_started_at < ?", @stale_before)
    end
  end
end
