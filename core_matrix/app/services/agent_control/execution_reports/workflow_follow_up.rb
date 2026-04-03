module AgentControl
  module ExecutionReports
    class WorkflowFollowUp
      def initialize(agent_task_run:, occurred_at:)
        @agent_task_run = agent_task_run
        @occurred_at = occurred_at
      end

      def apply!(lifecycle_state:)
        apply_wait_transition! if lifecycle_state == "completed"
        apply_retry_gate! if lifecycle_state == "failed"
        sync_subagent_session!(lifecycle_state: lifecycle_state)
        resume_parent_workflow_if_subagent_wait_resolved!
        refresh_workflow_after_terminal!(lifecycle_state: lifecycle_state)
      end

      private

      def apply_wait_transition!
        return if @agent_task_run.terminal_payload["wait_transition_requested"].blank?

        Workflows::HandleWaitTransitionRequest.call(
          agent_task_run: @agent_task_run,
          terminal_payload: @agent_task_run.terminal_payload,
          occurred_at: @occurred_at
        )
      end

      def apply_retry_gate!
        terminal_payload = @agent_task_run.terminal_payload
        return unless terminal_payload["retryable"]
        return unless terminal_payload["retry_scope"] == "step"

        @agent_task_run.workflow_run.update!(
          wait_state: "waiting",
          wait_reason_kind: "retryable_failure",
          wait_reason_payload: {
            "failure_kind" => terminal_payload["failure_kind"],
            "retryable" => true,
            "retry_scope" => "step",
            "logical_work_id" => @agent_task_run.logical_work_id,
            "attempt_no" => @agent_task_run.attempt_no,
            "last_error_summary" => terminal_payload["last_error_summary"],
          }.compact,
          waiting_since_at: @occurred_at,
          blocking_resource_type: "AgentTaskRun",
          blocking_resource_id: @agent_task_run.public_id
        )
      end

      def sync_subagent_session!(lifecycle_state:)
        session = @agent_task_run.subagent_session
        return if session.blank?

        observed_status =
          if @agent_task_run.workflow_run.reload.waiting?
            "waiting"
          elsif lifecycle_state == "completed"
            "completed"
          elsif lifecycle_state == "failed"
            "failed"
          else
            "interrupted"
          end

        session.update!(observed_status: observed_status)
      end

      def refresh_workflow_after_terminal!(lifecycle_state:)
        workflow_run = @agent_task_run.workflow_run.reload

        case lifecycle_state
        when "completed"
          Workflows::RefreshRunLifecycle.call(workflow_run: workflow_run)
          Workflows::DispatchRunnableNodes.call(workflow_run: workflow_run)
        when "failed"
          return if workflow_run.waiting?

          Workflows::RefreshRunLifecycle.call(workflow_run: workflow_run, terminal_state: "failed")
        end
      end

      def resume_parent_workflow_if_subagent_wait_resolved!
        return if @agent_task_run.subagent_session.blank?
        return if @agent_task_run.origin_turn.blank?

        parent_workflow_run = WorkflowRun.find_by(turn: @agent_task_run.origin_turn)
        return if parent_workflow_run.blank?
        return unless parent_workflow_run.waiting_on_subagent_barrier?

        Workflows::ResumeAfterWaitResolution.call(workflow_run: parent_workflow_run)
      end
    end
  end
end
