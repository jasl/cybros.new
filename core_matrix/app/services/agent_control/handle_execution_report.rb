module AgentControl
  class HandleExecutionReport
    TERMINAL_METHODS = %w[execution_complete execution_fail execution_interrupted].freeze

    def self.call(...)
      new(...).call
    end

    def initialize(deployment:, method_id:, payload:, occurred_at: Time.current)
      @deployment = deployment
      @method_id = method_id
      @payload = payload
      @occurred_at = occurred_at
    end

    def receipt_attributes
      {
        mailbox_item: mailbox_item,
        agent_task_run: agent_task_run,
      }
    end

    def call
      ValidateExecutionReportFreshness.call(
        deployment: @deployment,
        method_id: @method_id,
        payload: @payload,
        mailbox_item: mailbox_item,
        agent_task_run: agent_task_run,
        occurred_at: @occurred_at
      )

      case @method_id
      when "execution_started"
        handle_execution_started!
      when "execution_progress"
        handle_execution_progress!
      when *TERMINAL_METHODS
        handle_execution_terminal!
      else
        raise ArgumentError, "unsupported execution report #{@method_id}"
      end
    end

    private

    def handle_execution_started!
      agent_task_run.update!(
        lifecycle_state: "running",
        started_at: @occurred_at,
        holder_agent_deployment: @deployment,
        expected_duration_seconds: @payload["expected_duration_seconds"]
      )
      agent_task_run.workflow_node.update!(
        lifecycle_state: "running",
        started_at: agent_task_run.workflow_node.started_at || @occurred_at,
        finished_at: nil
      )

      unless agent_task_run.execution_lease&.active?
        Leases::Acquire.call(
          leased_resource: agent_task_run,
          holder_key: @deployment.public_id,
          heartbeat_timeout_seconds: mailbox_item.lease_timeout_seconds
        )
      end

      mailbox_item.update!(status: "acked", acked_at: @occurred_at)
      broadcast_runtime_event!(
        "runtime.agent_task.started",
        base_runtime_payload.merge(
          "expected_duration_seconds" => @payload["expected_duration_seconds"]
        )
      )
    end

    def handle_execution_progress!
      heartbeat_task_lease!
      progress_payload = @payload.fetch("progress_payload", {})
      agent_task_run.update!(progress_payload: progress_payload)
      broadcast_runtime_event!(
        "runtime.agent_task.progress",
        base_runtime_payload.merge(
          "progress_payload" => progress_payload
        )
      )
      apply_tool_invocation_progress!(progress_payload)
    end

    def handle_execution_terminal!
      heartbeat_task_lease!

      lifecycle_state = case @method_id
      when "execution_complete" then "completed"
      when "execution_fail" then "failed"
      else "interrupted"
      end

      agent_task_run.update!(
        lifecycle_state: lifecycle_state,
        terminal_payload: terminal_payload_for_terminal_message,
        finished_at: @occurred_at
      )
      agent_task_run.workflow_node.update!(
        lifecycle_state: workflow_node_terminal_state_for(lifecycle_state),
        started_at: agent_task_run.workflow_node.started_at || agent_task_run.started_at || @occurred_at,
        finished_at: @occurred_at
      )

      apply_tool_invocation_terminal_events!
      apply_wait_transition! if lifecycle_state == "completed"
      apply_retry_gate! if lifecycle_state == "failed"
      sync_subagent_session!(lifecycle_state: lifecycle_state)
      resume_parent_workflow_if_subagent_wait_resolved!
      refresh_workflow_after_terminal!(lifecycle_state: lifecycle_state)

      if agent_task_run.execution_lease&.active?
        Leases::Release.call(
          execution_lease: agent_task_run.execution_lease,
          holder_key: @deployment.public_id,
          reason: lifecycle_state,
          released_at: @occurred_at
        )
      end

      mailbox_item.update!(status: "completed", completed_at: @occurred_at)
      broadcast_runtime_event!(
        "runtime.agent_task.#{lifecycle_state}",
        base_runtime_payload.merge(
          "terminal_payload" => agent_task_run.terminal_payload,
          "lifecycle_state" => lifecycle_state
        )
      )
    end

    def apply_wait_transition!
      return if agent_task_run.terminal_payload["wait_transition_requested"].blank?

      Workflows::HandleWaitTransitionRequest.call(
        agent_task_run: agent_task_run,
        terminal_payload: agent_task_run.terminal_payload,
        occurred_at: @occurred_at
      )
    end

    def terminal_payload_for_terminal_message
      payload = @payload.fetch("terminal_payload", {}).deep_stringify_keys
      payload["terminal_method_id"] = @method_id
      payload
    end

    def apply_tool_invocation_progress!(progress_payload)
      invocation_payload = progress_payload["tool_invocation"]
      return if invocation_payload.blank?
      return unless invocation_payload["event"] == "started"

      find_or_start_tool_invocation!(invocation_payload)
    end

    def apply_tool_invocation_terminal_events!
      Array(agent_task_run.terminal_payload["tool_invocations"]).each do |invocation_payload|
        invocation = find_or_start_tool_invocation!(invocation_payload)

        case invocation_payload["event"]
        when "completed"
          ToolInvocations::Complete.call(
            tool_invocation: invocation,
            response_payload: invocation_payload.fetch("response_payload", {}),
            metadata: {
              "reported_via" => @method_id,
            }
          )
          broadcast_tool_invocation_event!(
            "runtime.tool_invocation.completed",
            tool_invocation: invocation.reload,
            payload: {
              "call_id" => invocation_payload["call_id"],
              "tool_name" => invocation_payload["tool_name"],
              "response_payload" => invocation_payload.fetch("response_payload", {}),
            }
          )
        when "failed"
          ToolInvocations::Fail.call(
            tool_invocation: invocation,
            error_payload: invocation_payload.fetch("error_payload", {}),
            metadata: {
              "reported_via" => @method_id,
            }
          )
          broadcast_tool_invocation_event!(
            "runtime.tool_invocation.failed",
            tool_invocation: invocation.reload,
            payload: {
              "call_id" => invocation_payload["call_id"],
              "tool_name" => invocation_payload["tool_name"],
              "error_payload" => invocation_payload.fetch("error_payload", {}),
            }
          )
        end
      end
    end

    def find_or_start_tool_invocation!(invocation_payload)
      binding = tool_binding_for!(invocation_payload.fetch("tool_name"))
      existing = binding.tool_invocations.find_by(idempotency_key: invocation_payload["call_id"])
      return existing if existing.present?

      invocation = ToolInvocations::Start.call(
        tool_binding: binding,
        request_payload: invocation_payload.fetch("request_payload", {}),
        idempotency_key: invocation_payload["call_id"],
        metadata: {
          "reported_via" => @method_id,
        }
      )
      broadcast_tool_invocation_event!(
        "runtime.tool_invocation.started",
        tool_invocation: invocation,
        payload: {
          "call_id" => invocation_payload["call_id"],
          "tool_name" => invocation_payload["tool_name"],
          "request_payload" => invocation_payload.fetch("request_payload", {}),
        }
      )
      invocation
    end

    def tool_binding_for!(tool_name)
      agent_task_run.tool_bindings
        .joins(:tool_definition)
        .find_by!(tool_definitions: { tool_name: tool_name })
    end

    def broadcast_tool_invocation_event!(event_kind, tool_invocation:, payload:)
      broadcast_runtime_event!(
        event_kind,
        base_runtime_payload.merge(
          "tool_invocation_id" => tool_invocation.public_id,
          "tool_name" => tool_invocation.tool_definition.tool_name
        ).merge(payload)
      )
    end

    def heartbeat_task_lease!
      Leases::Heartbeat.call(
        execution_lease: agent_task_run.execution_lease,
        holder_key: @deployment.public_id,
        occurred_at: @occurred_at
      )
    rescue ArgumentError, Leases::Heartbeat::StaleLeaseError
      raise Report::StaleReportError
    end

    def apply_retry_gate!
      terminal_payload = agent_task_run.terminal_payload
      return unless terminal_payload["retryable"]
      return unless terminal_payload["retry_scope"] == "step"

      agent_task_run.workflow_run.update!(
        wait_state: "waiting",
        wait_reason_kind: "retryable_failure",
        wait_reason_payload: {
          "failure_kind" => terminal_payload["failure_kind"],
          "retryable" => true,
          "retry_scope" => "step",
          "logical_work_id" => agent_task_run.logical_work_id,
          "attempt_no" => agent_task_run.attempt_no,
          "last_error_summary" => terminal_payload["last_error_summary"],
        }.compact,
        waiting_since_at: @occurred_at,
        blocking_resource_type: "AgentTaskRun",
        blocking_resource_id: agent_task_run.public_id
      )
    end

    def sync_subagent_session!(lifecycle_state:)
      session = agent_task_run.subagent_session
      return if session.blank?

      observed_status =
        if agent_task_run.workflow_run.reload.waiting?
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

    def workflow_node_terminal_state_for(agent_task_lifecycle_state)
      agent_task_lifecycle_state == "interrupted" ? "canceled" : agent_task_lifecycle_state
    end

    def refresh_workflow_after_terminal!(lifecycle_state:)
      workflow_run = agent_task_run.workflow_run.reload

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
      return if agent_task_run.subagent_session.blank?
      return if agent_task_run.origin_turn.blank?

      parent_workflow_run = WorkflowRun.find_by(turn: agent_task_run.origin_turn)
      return if parent_workflow_run.blank?
      return unless parent_workflow_run.waiting_on_subagent_barrier?

      Workflows::ResumeAfterWaitResolution.call(workflow_run: parent_workflow_run)
    end

    def mailbox_item
      @mailbox_item ||= AgentControlMailboxItem.find_by!(
        installation_id: @deployment.installation_id,
        public_id: @payload.fetch("mailbox_item_id")
      )
    end

    def agent_task_run
      @agent_task_run ||= AgentTaskRun.find_by!(
        installation_id: @deployment.installation_id,
        public_id: @payload.fetch("agent_task_run_id")
      )
    end

    def base_runtime_payload
      {
        "agent_task_run_id" => agent_task_run.public_id,
        "workflow_run_id" => agent_task_run.workflow_run.public_id,
        "workflow_node_id" => agent_task_run.workflow_node.public_id,
      }
    end

    def broadcast_runtime_event!(event_kind, payload)
      ConversationRuntime::Broadcast.call(
        conversation: agent_task_run.conversation,
        turn: agent_task_run.turn,
        event_kind: event_kind,
        payload: payload,
        occurred_at: @occurred_at
      )
    end
  end
end
