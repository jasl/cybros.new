module AgentControl
  class HandleExecutionReport
    TERMINAL_METHODS = %w[execution_complete execution_fail execution_interrupted].freeze

    def self.call(...)
      new(...).call
    end

    def initialize(agent_definition_version:, agent_connection: nil, execution_runtime_connection: nil, resource: nil, method_id:, payload:, occurred_at: Time.current, **)
      @agent_definition_version = agent_definition_version
      @agent_connection = agent_connection
      @execution_runtime_connection = execution_runtime_connection
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
        agent_definition_version: @agent_definition_version,
        agent_connection: resolved_agent_connection,
        execution_runtime_connection: @execution_runtime_connection,
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
      waiting_on_execution_runtime_request = blocked_on_execution_runtime_request?

      agent_task_run.update!(
        lifecycle_state: "running",
        started_at: @occurred_at,
        holder_agent_connection: resolved_agent_connection,
        expected_duration_seconds: @payload["expected_duration_seconds"],
        supervision_state: "running",
        last_progress_at: @occurred_at
      )
      unless waiting_on_execution_runtime_request
        agent_task_run.workflow_node.update!(
          lifecycle_state: "running",
          started_at: agent_task_run.workflow_node.started_at || @occurred_at,
          finished_at: nil
        )
      end
      sync_subagent_connection_started_state!

      unless agent_task_run.execution_lease&.active?
        Leases::Acquire.call(
          leased_resource: agent_task_run,
          holder_key: @agent_definition_version.public_id,
          heartbeat_timeout_seconds: mailbox_item.lease_timeout_seconds
        )
      end

      mailbox_item.update!(status: "acked", acked_at: @occurred_at)
      refresh_related_supervision_states!
      broadcast_runtime_event!(
        "runtime.agent_task.started",
        base_runtime_payload.merge(
          "expected_duration_seconds" => @payload["expected_duration_seconds"]
        )
      )
    end

    def handle_execution_progress!
      heartbeat_task_lease!
      progress_payload = @payload.fetch("progress_payload", {}).deep_stringify_keys
      agent_task_run.update!(progress_payload: progress_payload)
      broadcast_runtime_event!(
        "runtime.agent_task.progress",
        base_runtime_payload.merge(
          "progress_payload" => progress_payload
        )
      )
      apply_tool_invocation_progress!(progress_payload)
      apply_turn_todo_plan_update!(progress_payload)
      apply_supervision_update!(progress_payload)
    end

    def handle_execution_terminal!
      heartbeat_task_lease!
      waiting_on_execution_runtime_request = blocked_on_execution_runtime_request?

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
      unless waiting_on_execution_runtime_request
        agent_task_run.workflow_node.update!(
          lifecycle_state: workflow_node_terminal_state_for(lifecycle_state),
          started_at: agent_task_run.workflow_node.started_at || agent_task_run.started_at || @occurred_at,
          finished_at: @occurred_at
        )
      end

      apply_tool_invocation_terminal_events!
      terminalize_running_command_runs!(lifecycle_state: lifecycle_state)
      resume_blocked_workflow! if waiting_on_execution_runtime_request
      workflow_follow_up.apply!(lifecycle_state: lifecycle_state)
      append_terminal_progress_entry!(lifecycle_state: lifecycle_state)
      refresh_related_supervision_states!

      if agent_task_run.execution_lease&.active?
        Leases::Release.call(
          execution_lease: agent_task_run.execution_lease,
          holder_key: @agent_definition_version.public_id,
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

    def apply_supervision_update!(progress_payload)
      return if progress_payload["supervision_update"].blank?

      AgentControl::ApplySupervisionUpdate.call(
        agent_task_run: agent_task_run,
        payload: progress_payload,
        occurred_at: @occurred_at
      )
    end

    def apply_turn_todo_plan_update!(progress_payload)
      return if progress_payload["turn_todo_plan_update"].blank?

      TurnTodoPlans::ApplyUpdate.call(
        agent_task_run: agent_task_run,
        payload: progress_payload.fetch("turn_todo_plan_update"),
        occurred_at: @occurred_at
      )
      refresh_related_supervision_states!
    end

    def apply_tool_invocation_terminal_events!
      tool_invocation_reconciler.apply_terminal!(agent_task_run.terminal_payload)
    end

    def append_terminal_progress_entry!(lifecycle_state:)
      summary = terminal_summary_for(lifecycle_state:)

      agent_task_run.update!(
        supervision_state: lifecycle_state,
        recent_progress_summary: summary,
        waiting_summary: nil,
        blocked_summary: nil,
        last_progress_at: @occurred_at
      )
      sync_subagent_connection_terminal_state!(lifecycle_state:, summary:)

      AgentTaskRuns::AppendProgressEntry.call(
        agent_task_run: agent_task_run,
        subagent_connection: agent_task_run.progress_entry_subagent_connection,
        entry_kind: "execution_#{lifecycle_state}",
        summary: summary,
        details_payload: {},
        occurred_at: @occurred_at
      )
    end

    def sync_subagent_connection_started_state!
      session = agent_task_run.subagent_connection
      return if session.blank?

      session.update!(
        observed_status: "running",
        supervision_state: "running",
        last_progress_at: @occurred_at
      )
    end

    def sync_subagent_connection_terminal_state!(lifecycle_state:, summary:)
      session = agent_task_run.subagent_connection
      return if session.blank?

      observed_status =
        case lifecycle_state
        when "completed" then "completed"
        when "failed" then "failed"
        else "interrupted"
        end

      session.update!(
        supervision_state: lifecycle_state,
        observed_status: observed_status,
        recent_progress_summary: summary,
        waiting_summary: nil,
        blocked_summary: nil,
        last_progress_at: @occurred_at
      )
    end

    def blocked_on_execution_runtime_request?
      workflow_run = agent_task_run.workflow_run

      workflow_run.waiting? &&
        workflow_run.wait_reason_kind == "execution_runtime_request" &&
        workflow_run.blocking_resource_type == "WorkflowNode" &&
        workflow_run.blocking_resource_id == agent_task_run.workflow_node.public_id
    end

    def resume_blocked_workflow!
      Workflows::ResumeBlockedStep.call(workflow_run: agent_task_run.workflow_run)
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound
      nil
    end

    def terminal_summary_for(lifecycle_state:)
      fallback =
        case lifecycle_state
        when "completed" then "Completed the assigned work."
        when "failed" then "Execution failed."
        else "Execution was interrupted."
        end
      candidate =
        case lifecycle_state
        when "completed"
          terminal_payload_for_terminal_message["output"]
        when "failed"
          terminal_payload_for_terminal_message["last_error_summary"]
        end

      sanitize_terminal_summary(candidate, fallback:)
    end

    def sanitize_terminal_summary(candidate, fallback:)
      summary = candidate.to_s.gsub(AgentTaskProgressEntry::INTERNAL_RUNTIME_TOKEN_PATTERN, " ").squish
      summary = fallback if summary.blank?

      summary.truncate(SupervisionStateFields::HUMAN_SUMMARY_MAX_LENGTH)
    end

    def refresh_related_supervision_states!
      [agent_task_run.conversation, agent_task_run.subagent_connection&.owner_conversation].compact.uniq.each do |conversation|
        Conversations::UpdateSupervisionState.call(
          conversation: conversation,
          occurred_at: @occurred_at,
          include_runtime_evidence: @method_id != "execution_started"
        )
      end
    end

    def resolved_agent_connection
      @resolved_agent_connection ||= @agent_connection || @agent_definition_version.active_agent_connection || @agent_definition_version.most_recent_agent_connection
    end

    def heartbeat_task_lease!
      Leases::Heartbeat.call(
        execution_lease: agent_task_run.execution_lease,
        holder_key: @agent_definition_version.public_id,
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
        installation_id: @agent_definition_version.installation_id,
        public_id: @payload.fetch("mailbox_item_id")
      )
    end

    def agent_task_run
      @agent_task_run ||= AgentTaskRun.find_by!(
        installation_id: @agent_definition_version.installation_id,
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
      ConversationRuntime::PublishEvent.call(
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
