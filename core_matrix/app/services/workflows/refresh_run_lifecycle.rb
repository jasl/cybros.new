module Workflows
  class RefreshRunLifecycle
    ACTIVE_NODE_STATES = %w[pending queued running].freeze

    def self.call(...)
      new(...).call
    end

    def initialize(workflow_run:, terminal_state: nil)
      @workflow_run = workflow_run
      @terminal_state = terminal_state&.to_s
    end

    def call
      @workflow_run.with_lock do
        workflow_run = @workflow_run.reload
        return workflow_run unless workflow_run.active?
        return workflow_run if workflow_run.waiting?

        if @terminal_state.present?
          workflow_run.update!(lifecycle_state: @terminal_state)
          return workflow_run
        end

        active_nodes_exist = WorkflowNode.where(
          workflow_run: workflow_run,
          lifecycle_state: ACTIVE_NODE_STATES
        ).exists?
        return workflow_run if active_nodes_exist

        workflow_run.update!(lifecycle_state: "completed")
        workflow_run
      end
    end
  end
end
