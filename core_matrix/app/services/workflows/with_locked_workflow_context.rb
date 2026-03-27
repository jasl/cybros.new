module Workflows
  class WithLockedWorkflowContext
    def self.call(*args, **kwargs, &block)
      new(*args, **kwargs).call(&block)
    end

    def initialize(workflow_run:)
      @workflow_run = workflow_run
    end

    def call
      # Keep turn -> workflow_run lock order aligned with interrupt handling.
      current_turn.with_lock do
        current_workflow_run.with_lock do
          yield current_workflow_run.reload, current_turn.reload
        end
      end
    end

    private

    def current_workflow_run
      @current_workflow_run ||= WorkflowRun.find(@workflow_run.id)
    end

    def current_turn
      @current_turn ||= Turn.find(current_workflow_run.turn_id)
    end
  end
end
