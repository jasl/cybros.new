require "securerandom"

module AgentControl
  class CreateAgentProgramRequest
    REQUEST_KINDS = %w[
      prepare_round
      execute_program_tool
      supervision_status_refresh
      supervision_guidance
    ].freeze

    def self.call(...)
      new(...).call
    end

    def initialize(agent_program_version:, request_kind:, payload:, logical_work_id:, attempt_no: 1, dispatch_deadline_at:, execution_hard_deadline_at: nil, protocol_message_id: nil, causation_id: nil, lease_timeout_seconds: 30, priority: 1)
      @agent_program_version = agent_program_version
      @request_kind = request_kind.to_s
      @payload = payload.deep_stringify_keys
      @logical_work_id = logical_work_id
      @attempt_no = attempt_no.to_i
      @dispatch_deadline_at = dispatch_deadline_at
      @execution_hard_deadline_at = execution_hard_deadline_at
      @protocol_message_id = protocol_message_id || "kernel-program-request-#{SecureRandom.uuid}"
      @causation_id = causation_id
      @lease_timeout_seconds = lease_timeout_seconds
      @priority = priority
    end

    def call
      raise ArgumentError, "unsupported request kind #{@request_kind}" unless REQUEST_KINDS.include?(@request_kind)

      workflow_node = resolved_workflow_node
      execution_contract = workflow_node&.turn&.execution_contract

      mailbox_item = AgentControlMailboxItem.create!(
        installation: @agent_program_version.installation,
        target_agent_program: @agent_program_version.agent_program,
        target_agent_program_version: @agent_program_version,
        item_type: "agent_program_request",
        runtime_plane: "program",
        workflow_node: workflow_node,
        execution_contract: execution_contract,
        logical_work_id: @logical_work_id,
        attempt_no: @attempt_no,
        protocol_message_id: @protocol_message_id,
        causation_id: @causation_id,
        priority: @priority,
        status: "queued",
        available_at: Time.current,
        dispatch_deadline_at: @dispatch_deadline_at,
        lease_timeout_seconds: @lease_timeout_seconds,
        execution_hard_deadline_at: @execution_hard_deadline_at,
        payload_document: JsonDocuments::Store.call(
          installation: @agent_program_version.installation,
          document_kind: "agent_program_request",
          payload: request_payload(workflow_node:, execution_contract:)
        ),
        payload: { "request_kind" => @request_kind }
      )

      PublishPending.call(mailbox_item: mailbox_item)
      mailbox_item
    end

    private

    def request_payload(workflow_node:, execution_contract:)
      compact_request_payload(@payload, workflow_node:, execution_contract:)
    end

    def compact_request_payload(payload, workflow_node:, execution_contract:)
      compact = payload.deep_dup
      compact.delete("request_kind")
      compact.delete("protocol_version")
      compact.delete("provider_context") if execution_contract.present?
      compact.delete("agent_context") if execution_contract.present?
      compact.delete("round_context") if execution_contract.present? && @request_kind == "prepare_round"

      task = extract_task_payload(compact)
      if task.present?
        compact_task = task.deep_stringify_keys.except("workflow_node_id", "workflow_run_id", "conversation_id", "turn_id")
        compact_task.delete("kind") if workflow_node.present? && compact_task["kind"] == workflow_node.node_type

        if compact_task.present?
          compact["task"] = compact_task
        else
          compact.delete("task")
        end
      end

      runtime_context = compact["runtime_context"]
      return compact unless runtime_context.is_a?(Hash)

      compact_runtime_context =
        runtime_context.deep_stringify_keys.except(
          "logical_work_id",
          "attempt_no",
          "runtime_plane",
          "agent_program_version_id"
        )

      if compact_runtime_context.present?
        compact["runtime_context"] = compact_runtime_context
      else
        compact.delete("runtime_context")
      end

      compact
    end

    def resolved_workflow_node
      workflow_node_public_id = extract_task_payload(@payload)&.fetch("workflow_node_id", nil)
      return if workflow_node_public_id.blank?

      WorkflowNode.find_by!(
        installation_id: @agent_program_version.installation_id,
        public_id: workflow_node_public_id
      )
    end

    def extract_task_payload(payload)
      task = payload["task"]
      return task if task.is_a?(Hash)

      legacy_task = payload.slice("workflow_node_id", "workflow_run_id", "conversation_id", "turn_id", "kind")
      legacy_task.presence
    end
  end
end
