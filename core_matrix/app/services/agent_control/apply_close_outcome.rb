module AgentControl
  class ApplyCloseOutcome
    CLOSE_STATES = %w[closed failed].freeze

    def self.call(...)
      new(...).call
    end

    def initialize(resource:, mailbox_item:, close_state:, close_outcome_kind:, close_outcome_payload:, occurred_at: Time.current)
      @resource = resource
      @mailbox_item = mailbox_item
      @close_state = close_state
      @close_outcome_kind = close_outcome_kind
      @close_outcome_payload = close_outcome_payload
      @occurred_at = occurred_at
    end

    def call
      raise ArgumentError, "unsupported close state #{@close_state}" unless CLOSE_STATES.include?(@close_state)

      @resource.update!(
        close_state: @close_state,
        close_acknowledged_at: @resource.close_acknowledged_at || @occurred_at,
        close_outcome_kind: @close_outcome_kind,
        close_outcome_payload: @close_outcome_payload
      )

      terminalize_resource!
      @mailbox_item.update!(status: "completed", completed_at: @occurred_at)
      @resource
    end

    private

    def terminalize_resource!
      close_failed? ? terminalize_failed_resource! : terminalize_closed_resource!

      release_resource_lease!
      reconcile_turn_interrupt!
      reconcile_close_operation!
    end

    def terminalize_closed_resource!
      case @resource
      when AgentTaskRun
        @resource.update!(
          lifecycle_state: @mailbox_item.payload["request_kind"] == "turn_interrupt" ? "interrupted" : "canceled",
          finished_at: @resource.finished_at || @occurred_at,
          terminal_payload: @resource.terminal_payload.merge(
            "close_outcome_kind" => @resource.close_outcome_kind
          )
        )
        terminalize_agent_task_command_runs!("interrupted")
        reconcile_agent_task_execution_graph!
      when ProcessRun
        @resource.update!(
          lifecycle_state: @resource.close_outcome_kind == "residual_abandoned" ? "lost" : "stopped",
          ended_at: @resource.ended_at || @occurred_at,
          metadata: @resource.metadata.merge(
            "stop_reason" => @resource.close_reason_kind,
            "close_request_kind" => @mailbox_item.payload["request_kind"]
          )
        )
        broadcast_process_run_terminal!("runtime.process_run.#{@resource.lifecycle_state}")
      when SubagentSession
        @resource.update!(
          observed_status: terminal_observed_status
        )
      end
    end

    def terminalize_failed_resource!
      case @resource
      when AgentTaskRun
        @resource.update!(
          lifecycle_state: "failed",
          finished_at: @resource.finished_at || @occurred_at,
          terminal_payload: @resource.terminal_payload.merge(
            "close_outcome_kind" => @resource.close_outcome_kind,
            "close_request_kind" => @mailbox_item.payload["request_kind"]
          )
        )
        terminalize_agent_task_command_runs!("failed")
        reconcile_agent_task_execution_graph!
      when ProcessRun
        @resource.update!(
          lifecycle_state: "lost",
          ended_at: @resource.ended_at || @occurred_at,
          metadata: @resource.metadata.merge(
            "stop_reason" => @resource.close_reason_kind,
            "close_request_kind" => @mailbox_item.payload["request_kind"]
          )
        )
        broadcast_process_run_terminal!("runtime.process_run.lost")
      when SubagentSession
        @resource.update!(
          observed_status: "failed"
        )
      end
    end

    def release_resource_lease!
      return unless @resource.respond_to?(:execution_lease)

      execution_lease = @resource.execution_lease
      return unless execution_lease&.active?

      Leases::Release.call(
        execution_lease: execution_lease,
        holder_key: execution_lease.holder_key,
        reason: close_failed? ? "resource_close_failed" : "resource_closed",
        released_at: @occurred_at
      )
    rescue ArgumentError
      nil
    end

    def reconcile_turn_interrupt!
      turn = ClosableResourceRouting.turn_for(@resource)
      return if turn.blank?
      return unless turn.cancellation_reason_kind == "turn_interrupted"

      Conversations::RequestTurnInterrupt.call(turn: turn, occurred_at: @occurred_at)
    end

    def reconcile_close_operation!
      conversations_for_close_reconciliation.each do |conversation|
        Conversations::ReconcileCloseOperation.call(
          conversation: conversation,
          occurred_at: @occurred_at
        )
      end
    end

    def close_failed?
      @close_state == "failed"
    end

    def terminal_observed_status
      return "interrupted" if @mailbox_item.payload["request_kind"] == "turn_interrupt"

      "completed"
    end

    def reconcile_agent_task_execution_graph!
      return unless @resource.is_a?(AgentTaskRun)

      reconcile_agent_task_workflow_node!
      reconcile_agent_task_workflow_run!
      reconcile_agent_task_turn!
    end

    def terminalize_agent_task_command_runs!(lifecycle_state)
      return unless @resource.is_a?(AgentTaskRun)

      @resource.command_runs.running.find_each do |command_run|
        CommandRuns::Terminalize.call(
          command_run: command_run,
          lifecycle_state: lifecycle_state,
          ended_at: @occurred_at
        )
      end
    end

    def reconcile_agent_task_workflow_node!
      workflow_node = @resource.workflow_node
      return if workflow_node.blank?

      terminal_state = @resource.failed? ? "failed" : "canceled"
      started_at = workflow_node.started_at || @resource.started_at || @occurred_at

      workflow_node.with_lock do
        workflow_node.reload

        workflow_node.update!(
          lifecycle_state: terminal_state,
          started_at: terminal_state == "canceled" ? workflow_node.started_at || @resource.started_at : started_at,
          finished_at: workflow_node.finished_at || @occurred_at
        )

        WorkflowNodeEvent.create!(
          installation: workflow_node.installation,
          workflow_run: workflow_node.workflow_run,
          workflow_node: workflow_node,
          ordinal: workflow_node.workflow_node_events.maximum(:ordinal).to_i + 1,
          event_kind: "status",
          payload: {
            "state" => terminal_state,
            "close_state" => @resource.close_state,
            "close_outcome_kind" => @resource.close_outcome_kind,
          }
        )
      end
    end

    def reconcile_agent_task_workflow_run!
      workflow_run = @resource.workflow_run
      return if workflow_run.blank? || !workflow_run.active?

      lifecycle_state = @resource.failed? ? "failed" : "canceled"
      updates = { lifecycle_state: lifecycle_state }.merge(Workflows::WaitState.ready_attributes)

      if @mailbox_item.payload["request_kind"] == "turn_interrupt"
        updates[:cancellation_requested_at] = workflow_run.cancellation_requested_at || @occurred_at
        updates[:cancellation_reason_kind] = "turn_interrupted"
      end

      workflow_run.update!(updates)
    end

    def reconcile_agent_task_turn!
      turn = @resource.turn
      return if turn.blank? || !turn.active?

      lifecycle_state = @resource.failed? ? "failed" : "canceled"
      updates = { lifecycle_state: lifecycle_state }

      if @mailbox_item.payload["request_kind"] == "turn_interrupt"
        updates[:cancellation_requested_at] = turn.cancellation_requested_at || @occurred_at
        updates[:cancellation_reason_kind] = "turn_interrupted"
      end

      turn.update!(updates)
    end

    def broadcast_process_run_terminal!(event_kind)
      return unless @resource.is_a?(ProcessRun)

      Processes::BroadcastRuntimeEvent.call(
        process_run: @resource,
        event_kind: event_kind,
        occurred_at: @occurred_at,
        payload: {
          "close_state" => @resource.close_state,
          "close_outcome_kind" => @resource.close_outcome_kind,
          "close_outcome_payload" => @resource.close_outcome_payload,
        }
      )
    end

    def conversations_for_close_reconciliation
      conversations = [ClosableResourceRouting.conversation_for(@resource)]
      conversations << @resource.conversation if @resource.is_a?(SubagentSession)

      conversations.compact.uniq
    end
  end
end
