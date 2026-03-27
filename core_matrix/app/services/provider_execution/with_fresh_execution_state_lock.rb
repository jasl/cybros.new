module ProviderExecution
  class WithFreshExecutionStateLock
    StaleExecutionError = Class.new(StandardError)

    def self.call(*args, **kwargs, &block)
      new(*args, **kwargs).call(&block)
    end

    def initialize(workflow_node:)
      @workflow_node = workflow_node
      @workflow_run = workflow_node.workflow_run
      @turn = workflow_node.turn
    end

    def call
      @turn.with_lock do
        @workflow_run.with_lock do
          @workflow_node.with_lock do
            @turn.reload
            @workflow_run.reload
            @workflow_node.reload
            ensure_execution_still_fresh!
            yield @workflow_node, @workflow_run, @turn
          end
        end
      end
    end

    private

    def ensure_execution_still_fresh!
      return if @turn.active? &&
        @workflow_run.active? &&
        @workflow_run.ready? &&
        @turn.cancellation_requested_at.blank? &&
        @workflow_run.cancellation_requested_at.blank? &&
        terminal_event_state.blank?

      raise StaleExecutionError, "provider execution result is stale"
    end

    def terminal_event_state
      @workflow_node.workflow_node_events
        .where(event_kind: "status")
        .order(ordinal: :desc)
        .limit(1)
        .pick(Arel.sql("payload ->> 'state'"))
        .presence_in(%w[completed failed canceled])
    end
  end
end
