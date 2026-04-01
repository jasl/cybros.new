module Workflows
  class RetryPausedTurn < ResumePausedTurn
    def initialize(workflow_run:, occurred_at: Time.current)
      super(workflow_run: workflow_run, occurred_at: occurred_at, delivery_kind: "paused_retry")
    end
  end
end
