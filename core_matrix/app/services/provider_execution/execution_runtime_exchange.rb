module ProviderExecution
  class ExecutionRuntimeExchange
    DEFAULT_EXECUTE_TOOL_TIMEOUT = 5.minutes
    DEFAULT_LEASE_GRACE = 10.seconds

    class ExchangeError < ProviderExecution::AgentRequestExchange::ExchangeError; end
    class ProtocolError < ProviderExecution::AgentRequestExchange::ProtocolError; end
    class TimeoutError < ProviderExecution::AgentRequestExchange::TimeoutError; end
    class PendingResponse < ProviderExecution::AgentRequestExchange::PendingResponse; end
    class RequestFailed < ProviderExecution::AgentRequestExchange::RequestFailed; end

    PENDING_METADATA_KEY = Workflows::BlockNodeForExecutionRuntimeRequest::METADATA_KEY

    def self.call(...)
      new(...).call
    end

    def initialize(execution_runtime:, timeout: DEFAULT_EXECUTE_TOOL_TIMEOUT, lease_grace: DEFAULT_LEASE_GRACE)
      @execution_runtime = execution_runtime
      @timeout = timeout
      @lease_grace = lease_grace
    end

    def execute_tool(payload:, binding:)
      payload = payload.deep_stringify_keys
      workflow_node = resolved_workflow_node_for(payload)
      raise ProtocolError.new(code: "missing_workflow_node_id", message: "execution runtime requests must target a workflow node") if workflow_node.blank?

      logical_work_id = "tool-call:#{workflow_node.public_id}:#{payload.fetch("tool_call").fetch("call_id")}"
      pending_state = pending_exchange_state_for(workflow_node, request_kind: "execute_tool", logical_work_id:)

      if pending_state.present?
        mailbox_item = pending_mailbox_item_for!(workflow_node, pending_state)
        clear_pending_exchange_state!(workflow_node) if request_timed_out?(mailbox_item)
        raise TimeoutError.new(
          code: "mailbox_timeout",
          message: "timed out waiting for execution runtime report",
          details: { "mailbox_item_id" => mailbox_item.public_id },
          retryable: true
        ) if request_timed_out?(mailbox_item)

        Workflows::BlockNodeForExecutionRuntimeRequest.call(
          workflow_node: workflow_node,
          mailbox_item: mailbox_item,
          request_kind: "execute_tool",
          logical_work_id: logical_work_id,
          deadline_at: mailbox_item.dispatch_deadline_at || mailbox_item.execution_hard_deadline_at,
          occurred_at: Time.current
        )
        raise PendingResponse.new(
          mailbox_item_public_id: mailbox_item.public_id,
          logical_work_id: logical_work_id,
          request_kind: "execute_tool"
        )
      end

      started_at = Time.current
      agent_task_run = create_tool_call_task_run!(workflow_node:, binding:, payload:, logical_work_id:)
      mailbox_item = AgentControl::CreateExecutionAssignment.call(
        agent_task_run: agent_task_run,
        payload: assignment_payload(payload),
        dispatch_deadline_at: started_at + @timeout,
        execution_hard_deadline_at: started_at + @timeout,
        lease_timeout_seconds: [@timeout.to_f.ceil + @lease_grace.to_i, 1].max
      )

      Workflows::BlockNodeForExecutionRuntimeRequest.call(
        workflow_node: workflow_node,
        mailbox_item: mailbox_item,
        request_kind: "execute_tool",
        logical_work_id: logical_work_id,
        deadline_at: mailbox_item.dispatch_deadline_at || mailbox_item.execution_hard_deadline_at,
        occurred_at: started_at
      )

      raise PendingResponse.new(
        mailbox_item_public_id: mailbox_item.public_id,
        logical_work_id: logical_work_id,
        request_kind: "execute_tool"
      )
    end

    private

    def resolved_workflow_node_for(payload)
      workflow_node_public_id = payload.dig("task", "workflow_node_id")
      return if workflow_node_public_id.blank?

      WorkflowNode.find_by!(
        installation_id: @execution_runtime.installation_id,
        public_id: workflow_node_public_id
      )
    end

    def pending_exchange_state_for(workflow_node, request_kind:, logical_work_id:)
      state = workflow_node.metadata.fetch(PENDING_METADATA_KEY, nil)
      return unless state.is_a?(Hash)
      return unless state["request_kind"] == request_kind
      return unless state["logical_work_id"] == logical_work_id

      state
    end

    def pending_mailbox_item_for!(workflow_node, pending_state)
      AgentControlMailboxItem.find_by!(
        installation_id: workflow_node.installation_id,
        workflow_node: workflow_node,
        public_id: pending_state.fetch("mailbox_item_id"),
        item_type: "execution_assignment"
      )
    rescue ActiveRecord::RecordNotFound
      clear_pending_exchange_state!(workflow_node)
      raise ProtocolError.new(
        code: "missing_mailbox_request",
        message: "pending execution runtime request is missing its mailbox item",
        details: { "workflow_node_id" => workflow_node.public_id }
      )
    end

    def request_timed_out?(mailbox_item)
      deadline_at = mailbox_item.dispatch_deadline_at || mailbox_item.execution_hard_deadline_at
      deadline_at.present? && Time.current >= deadline_at
    end

    def clear_pending_exchange_state!(workflow_node)
      metadata = workflow_node.metadata
      return unless metadata.key?(PENDING_METADATA_KEY)

      workflow_node.update!(metadata: metadata.except(PENDING_METADATA_KEY))
    end

    def create_tool_call_task_run!(workflow_node:, binding:, payload:, logical_work_id:)
      attempt_no = AgentTaskRun.where(
        workflow_node: workflow_node,
        logical_work_id: logical_work_id
      ).maximum(:attempt_no).to_i + 1

      agent_task_run = AgentTaskRun.create!(
        installation: workflow_node.installation,
        agent: workflow_node.turn.agent_snapshot.agent,
        workflow_run: workflow_node.workflow_run,
        workflow_node: workflow_node,
        conversation: workflow_node.conversation,
        turn: workflow_node.turn,
        kind: "agent_tool_call",
        lifecycle_state: "queued",
        logical_work_id: logical_work_id,
        attempt_no: attempt_no,
        task_payload: {
          "mode" => "tool_call",
          "tool_name" => payload.dig("tool_call", "tool_name"),
          "call_id" => payload.dig("tool_call", "call_id"),
        },
        progress_payload: {},
        terminal_payload: {}
      )

      mirrored_binding = agent_task_run.tool_bindings.joins(:tool_definition).find_by!(
        tool_definitions: { tool_name: binding.tool_definition.tool_name }
      )
      mirrored_binding.update!(
        workflow_node: workflow_node,
        tool_implementation: binding.tool_implementation,
        source_workflow_node: workflow_node,
        source_tool_binding: binding,
        runtime_state: binding.runtime_state.deep_dup,
        parallel_safe: binding.parallel_safe,
        round_scoped: binding.round_scoped
      )

      agent_task_run
    end

    def assignment_payload(payload)
      {
        "task_payload" => {
          "mode" => "tool_call",
        },
        "tool_call" => payload.fetch("tool_call"),
        "runtime_resource_refs" => payload.fetch("runtime_resource_refs", {}),
      }
    end
  end
end
