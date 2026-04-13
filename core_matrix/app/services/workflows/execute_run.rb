module Workflows
  class ExecuteRun
    def self.call(...)
      new(...).call
    end

    def initialize(workflow_run:, workflow_node_key: nil)
      @workflow_run = workflow_run
      @workflow_node_key = workflow_node_key&.to_s
    end

    def call
      runnable_turn_steps = resolve_runnable_turn_steps
      workflow_node = resolve_workflow_node!(runnable_turn_steps)

      Workflows::DispatchRunnableNodes.call(
        workflow_run: @workflow_run,
        runnable_nodes: [workflow_node]
      ).first
    end

    private

    def resolve_runnable_turn_steps
      Workflows::Scheduler.call(workflow_run: @workflow_run).select { |node| node.node_type == "turn_step" }
    end

    def resolve_workflow_node!(runnable_turn_steps)
      return resolve_by_key!(runnable_turn_steps) if @workflow_node_key.present?
      return runnable_turn_steps.first if runnable_turn_steps.one?

      raise_invalid!(
        @workflow_run,
        :base,
        "must have exactly one runnable turn_step when no workflow node key is provided"
      )
    end

    def resolve_by_key!(runnable_turn_steps)
      workflow_node = @workflow_run.workflow_nodes.find_by!(node_key: @workflow_node_key)
      return workflow_node if runnable_turn_steps.any? { |candidate| candidate.id == workflow_node.id }

      raise_invalid!(@workflow_run, :base, "references a workflow node that is not runnable")
    rescue ActiveRecord::RecordNotFound
      raise_invalid!(@workflow_run, :base, "references unknown workflow node key #{@workflow_node_key}")
    end

    def raise_invalid!(record, attribute, message)
      record.errors.add(attribute, message)
      raise ActiveRecord::RecordInvalid, record
    end
  end
end
