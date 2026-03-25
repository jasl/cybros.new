module Workflows
  class ExecuteRun
    def self.call(...)
      new(...).call
    end

    def initialize(workflow_run:, workflow_node_key: nil, messages: nil, adapter: nil)
      @workflow_run = workflow_run
      @workflow_node_key = workflow_node_key&.to_s
      @messages = messages
      @adapter = adapter
    end

    def call
      ProviderExecution::ExecuteTurnStep.call(
        workflow_node: resolve_workflow_node!,
        messages: @messages || default_messages,
        adapter: @adapter
      )
    end

    private

    def resolve_workflow_node!
      return resolve_by_key! if @workflow_node_key.present?

      runnable_turn_steps = Workflows::Scheduler.call(workflow_run: @workflow_run).select { |node| node.node_type == "turn_step" }

      if runnable_turn_steps.one?
        return runnable_turn_steps.first
      end

      raise_invalid!(
        @workflow_run,
        :base,
        "must have exactly one runnable turn_step when no workflow node key is provided"
      )
    end

    def resolve_by_key!
      @workflow_run.workflow_nodes.find_by!(node_key: @workflow_node_key)
    rescue ActiveRecord::RecordNotFound
      raise_invalid!(@workflow_run, :base, "references unknown workflow node key #{@workflow_node_key}")
    end

    def default_messages
      @workflow_run.turn.context_messages.map { |entry| entry.slice("role", "content") }
    end

    def raise_invalid!(record, attribute, message)
      record.errors.add(attribute, message)
      raise ActiveRecord::RecordInvalid, record
    end
  end
end
