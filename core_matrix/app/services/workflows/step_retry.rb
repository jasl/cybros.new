module Workflows
  class StepRetry
    def self.call(...)
      new(...).call
    end

    def initialize(workflow_run:, occurred_at: Time.current)
      @workflow_run = workflow_run
      @occurred_at = occurred_at
    end

    def call
      validate_retry_gate!
      failed_task = blocking_agent_task

      ApplicationRecord.transaction do
        retried_task = AgentTaskRun.create!(
          installation: failed_task.installation,
          agent_installation: failed_task.agent_installation,
          workflow_run: failed_task.workflow_run,
          workflow_node: failed_task.workflow_node,
          conversation: failed_task.conversation,
          turn: failed_task.turn,
          task_kind: failed_task.task_kind,
          lifecycle_state: "queued",
          logical_work_id: failed_task.logical_work_id,
          attempt_no: failed_task.attempt_no + 1,
          task_payload: failed_task.task_payload,
          progress_payload: {},
          terminal_payload: {}
        )

        AgentControl::CreateExecutionAssignment.call(
          agent_task_run: retried_task,
          payload: failed_task.task_payload.merge(
            "delivery_kind" => "step_retry",
            "previous_attempt_no" => failed_task.attempt_no
          ),
          dispatch_deadline_at: @occurred_at + 5.minutes,
          execution_hard_deadline_at: @occurred_at + 10.minutes,
          priority: 2
        )

        @workflow_run.update!(
          wait_state: "ready",
          wait_reason_kind: nil,
          wait_reason_payload: {},
          waiting_since_at: nil,
          blocking_resource_type: nil,
          blocking_resource_id: nil
        )

        retried_task
      end
    end

    private

    def validate_retry_gate!
      unless @workflow_run.waiting? && @workflow_run.wait_reason_kind == "retryable_failure"
        raise_invalid!(@workflow_run, :wait_reason_kind, "must be retryable_failure before step retry")
      end

      if Turn.find(@workflow_run.turn_id).cancellation_reason_kind == "turn_interrupted"
        raise_invalid!(@workflow_run, :turn, "must not be fenced by turn interrupt")
      end

      unless @workflow_run.wait_reason_payload["retry_scope"] == "step"
        raise_invalid!(@workflow_run, :wait_reason_payload, "must use step retry scope")
      end
    end

    def blocking_agent_task
      AgentTaskRun.find_by!(
        workflow_run: @workflow_run,
        public_id: @workflow_run.blocking_resource_id
      )
    end

    def raise_invalid!(record, attribute, message)
      record.errors.add(attribute, message)
      raise ActiveRecord::RecordInvalid, record
    end
  end
end
