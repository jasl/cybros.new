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

      ApplicationRecord.transaction do
        Workflows::WithMutableWorkflowContext.call(
          workflow_run: @workflow_run,
          retained_message: "must be retained before step retry",
          active_message: "must be active before step retry",
          closing_message: "must not retry a failed step while close is in progress"
        ) do |_conversation, workflow_run, turn|
          validate_retry_gate!(workflow_run: workflow_run, turn: turn)

          with_failed_task_lock(workflow_run) do |failed_task|
            validate_retry_gate!(workflow_run: workflow_run.reload, turn: turn.reload)

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
              payload: {
                "task_payload" => failed_task.task_payload.merge(
                  "delivery_kind" => "step_retry",
                  "previous_attempt_no" => failed_task.attempt_no
                ),
              },
              dispatch_deadline_at: @occurred_at + 5.minutes,
              execution_hard_deadline_at: @occurred_at + 10.minutes,
              priority: 2
            )

            workflow_run.update!(Workflows::WaitState.ready_attributes)

            retried_task
          end
        end
      end
    end

    private

    def validate_retry_gate!(workflow_run: @workflow_run, turn: @workflow_run.turn)
      unless workflow_run.waiting? && workflow_run.wait_reason_kind == "retryable_failure"
        raise_invalid!(workflow_run, :wait_reason_kind, "must be retryable_failure before step retry")
      end

      if turn.cancellation_reason_kind == "turn_interrupted"
        raise_invalid!(workflow_run, :turn, "must not be fenced by turn interrupt")
      end

      unless workflow_run.wait_reason_payload["retry_scope"] == "step"
        raise_invalid!(workflow_run, :wait_reason_payload, "must use step retry scope")
      end
    end

    def with_failed_task_lock(workflow_run)
      failed_task = blocking_agent_task(workflow_run)

      failed_task.with_lock do
        yield failed_task.reload
      end
    end

    def blocking_agent_task(workflow_run)
      AgentTaskRun.find_by!(
        workflow_run: workflow_run,
        public_id: workflow_run.blocking_resource_id
      )
    end

    def raise_invalid!(record, attribute, message)
      record.errors.add(attribute, message)
      raise ActiveRecord::RecordInvalid, record
    end
  end
end
