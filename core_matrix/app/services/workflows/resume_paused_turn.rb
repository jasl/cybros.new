module Workflows
  class ResumePausedTurn
    def self.call(...)
      new(...).call
    end

    def initialize(workflow_run:, occurred_at: Time.current, delivery_kind: "turn_resume")
      @workflow_run = workflow_run
      @occurred_at = occurred_at
      @delivery_kind = delivery_kind
    end

    def call
      @workflow_run.reload
      validate_paused_state!

      ApplicationRecord.transaction do
        Workflows::WithMutableWorkflowContext.call(
          workflow_run: @workflow_run,
          retained_message: "must be retained before resuming paused work",
          active_message: "must be active before resuming paused work",
          closing_message: "must not resume paused work while close is in progress"
        ) do |conversation, workflow_run, turn|
          validate_paused_state!(workflow_run)
          paused_task = paused_task_run(workflow_run)

          workflow_run.update!(Workflows::TurnPauseState.resume_attributes(workflow_run: workflow_run))
          return workflow_run if workflow_run.reload.waiting?

          Workflows::BuildExecutionSnapshot.call(turn: turn.reload)

          create_next_attempt!(workflow_run:, turn:, paused_task:)
          workflow_run.reload
        end
      end
    end

    private

    def validate_paused_state!(workflow_run = @workflow_run)
      return if workflow_run.paused_turn?

      raise_invalid!(workflow_run, :wait_reason_kind, "must be paused before resuming")
    end

    def paused_task_run(workflow_run)
      paused_task_run_id = workflow_run.wait_reason_payload["paused_agent_task_run_id"]
      raise_invalid!(workflow_run, :wait_reason_payload, "must include a paused agent task run") if paused_task_run_id.blank?

      AgentTaskRun.find_by!(
        workflow_run: workflow_run,
        public_id: paused_task_run_id
      )
    end

    def create_next_attempt!(workflow_run:, turn:, paused_task:)
      paused_task.with_lock do
        next_attempt_no = paused_task.attempt_no + 1
        existing_task = AgentTaskRun.find_by(
          workflow_run: workflow_run,
          logical_work_id: paused_task.logical_work_id,
          attempt_no: next_attempt_no
        )
        return existing_task if existing_task.present?

        retried_task = AgentTaskRun.create!(
          installation: paused_task.installation,
          agent_program: paused_task.agent_program,
          workflow_run: paused_task.workflow_run,
          workflow_node: paused_task.workflow_node,
          conversation: paused_task.conversation,
          turn: turn,
          kind: paused_task.kind,
          lifecycle_state: "queued",
          logical_work_id: paused_task.logical_work_id,
          attempt_no: next_attempt_no,
          task_payload: next_task_payload(paused_task, workflow_run: workflow_run),
          progress_payload: {},
          terminal_payload: {}
        )

        paused_task.workflow_node.update!(
          lifecycle_state: "queued",
          started_at: nil,
          finished_at: nil
        )

        AgentControl::CreateExecutionAssignment.call(
          agent_task_run: retried_task,
          payload: { "task_payload" => retried_task.task_payload },
          dispatch_deadline_at: @occurred_at + 5.minutes,
          execution_hard_deadline_at: @occurred_at + 10.minutes,
          priority: 2
        )
      end
    end

    def next_task_payload(paused_task, workflow_run:)
      workflow_payload = workflow_run.wait_reason_payload.deep_stringify_keys

      paused_task.task_payload.deep_stringify_keys.merge(
        "delivery_kind" => @delivery_kind,
        "previous_attempt_no" => paused_task.attempt_no,
        "paused_agent_task_run_id" => paused_task.public_id,
        "paused_progress_payload" => workflow_payload["paused_progress_payload"] || paused_task.progress_payload.deep_stringify_keys,
        "paused_terminal_payload" => workflow_payload["paused_terminal_payload"] || paused_task.terminal_payload.deep_stringify_keys
      )
    end

    def raise_invalid!(record, attribute, message)
      record.errors.add(attribute, message)
      raise ActiveRecord::RecordInvalid, record
    end
  end
end
