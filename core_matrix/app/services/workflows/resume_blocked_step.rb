module Workflows
  class ResumeBlockedStep
    def self.call(...)
      new(...).call
    end

    def initialize(workflow_run:)
      @workflow_run = workflow_run
    end

    def call
      Workflows::WithMutableWorkflowContext.call(
        workflow_run: @workflow_run,
        retained_message: "must be retained before resuming a blocked step",
        active_message: "must be active before resuming a blocked step",
        closing_message: "must not resume a blocked step while close is in progress"
      ) do |_conversation, workflow_run, turn|
        return workflow_run unless workflow_run.waiting?
        raise_invalid!(workflow_run, :blocking_resource_type, "must block on a workflow node before resuming") unless workflow_run.blocking_resource_type == "WorkflowNode"
        raise_invalid!(turn, :cancellation_reason_kind, "must not be fenced by turn interrupt") if turn.cancellation_reason_kind == "turn_interrupted"

        workflow_node = WorkflowNode.find_by!(
          workflow_run: workflow_run,
          public_id: workflow_run.blocking_resource_id
        )
        raise_invalid!(workflow_node, :lifecycle_state, "must be waiting before resume") unless workflow_node.waiting?

        workflow_node.update!(
          lifecycle_state: "pending",
          started_at: nil,
          finished_at: nil
        )
        turn.update!(lifecycle_state: "active")
        workflow_run.update!(Workflows::WaitState.ready_attributes)
        Workflows::DispatchRunnableNodes.call(workflow_run: workflow_run)
        workflow_node
      end
    end

    private

    def raise_invalid!(record, attribute, message)
      record.errors.add(attribute, message)
      raise ActiveRecord::RecordInvalid, record
    end
  end
end
