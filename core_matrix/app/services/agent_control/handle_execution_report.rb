module AgentControl
  class HandleExecutionReport
    TERMINAL_METHODS = %w[execution_complete execution_fail execution_interrupted].freeze

    def self.call(...)
      new(...).call
    end

    def initialize(deployment:, agent_session: nil, execution_session: nil, method_id:, payload:, occurred_at: Time.current)
      @deployment = deployment
      @agent_session = agent_session
      @execution_session = execution_session
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
        agent_session: resolved_agent_session,
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
        holder_agent_session: resolved_agent_session,
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
      terminalize_running_command_runs!(lifecycle_state: lifecycle_state)
      workflow_follow_up.apply!(lifecycle_state: lifecycle_state)

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

    def terminal_payload_for_terminal_message
      payload = @payload.fetch("terminal_payload", {}).deep_stringify_keys
      payload["terminal_method_id"] = @method_id
      payload
    end

    def apply_tool_invocation_progress!(progress_payload)
      tool_invocation_reconciler.apply_progress!(progress_payload)
    end

    def apply_tool_invocation_terminal_events!
      tool_invocation_reconciler.apply_terminal!(agent_task_run.terminal_payload)
    end

    def resolved_agent_session
      @resolved_agent_session ||= @agent_session || @deployment.active_agent_session || @deployment.most_recent_agent_session
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

    def workflow_node_terminal_state_for(agent_task_lifecycle_state)
      agent_task_lifecycle_state == "interrupted" ? "canceled" : agent_task_lifecycle_state
    end

    def terminalize_running_command_runs!(lifecycle_state:)
      terminal_command_state =
        case lifecycle_state
        when "failed" then "failed"
        when "interrupted", "canceled" then "interrupted"
        end
      return if terminal_command_state.blank?

      agent_task_run.command_runs.where(lifecycle_state: %w[starting running]).find_each do |command_run|
        CommandRuns::Terminalize.call(
          command_run: command_run,
          lifecycle_state: terminal_command_state,
          ended_at: @occurred_at
        )
      end
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

    def tool_invocation_reconciler
      @tool_invocation_reconciler ||= AgentControl::ExecutionReports::ToolInvocationReconciler.new(
        agent_task_run: agent_task_run,
        method_id: @method_id,
        occurred_at: @occurred_at,
        base_runtime_payload: base_runtime_payload,
        broadcast_runtime_event: method(:broadcast_runtime_event!)
      )
    end

    def workflow_follow_up
      @workflow_follow_up ||= AgentControl::ExecutionReports::WorkflowFollowUp.new(
        agent_task_run: agent_task_run,
        occurred_at: @occurred_at
      )
    end
  end
end
