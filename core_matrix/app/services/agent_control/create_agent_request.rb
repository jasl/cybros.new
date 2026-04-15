require "securerandom"

module AgentControl
  class CreateAgentRequest
    REQUEST_KINDS = %w[
      prepare_round
      execute_tool
      execute_feature
      consult_prompt_compaction
      execute_prompt_compaction
      supervision_status_refresh
      supervision_guidance
    ].freeze

    def self.call(...)
      new(...).call
    end

    def initialize(agent_definition_version:, request_kind:, payload:, logical_work_id:, attempt_no: 1, dispatch_deadline_at:, execution_hard_deadline_at: nil, protocol_message_id: nil, causation_id: nil, lease_timeout_seconds: 30, priority: 1)
      @agent_definition_version = agent_definition_version
      @request_kind = request_kind.to_s
      @payload = payload.deep_stringify_keys
      @logical_work_id = logical_work_id
      @attempt_no = attempt_no.to_i
      @dispatch_deadline_at = dispatch_deadline_at
      @execution_hard_deadline_at = execution_hard_deadline_at
      @protocol_message_id = protocol_message_id || "kernel-agent-request-#{SecureRandom.uuid}"
      @causation_id = causation_id
      @lease_timeout_seconds = lease_timeout_seconds
      @priority = priority
    end

    def call
      raise ArgumentError, "unsupported request kind #{@request_kind}" unless REQUEST_KINDS.include?(@request_kind)
      validate_task_payload!

      workflow_node = resolved_workflow_node
      execution_contract = workflow_node&.turn&.execution_contract

      mailbox_item = AgentControlMailboxItem.create!(
        installation: @agent_definition_version.installation,
        target_agent: @agent_definition_version.agent,
        target_agent_definition_version: @agent_definition_version,
        item_type: "agent_request",
        control_plane: "agent",
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
          installation: @agent_definition_version.installation,
          document_kind: "agent_request",
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
      if execution_contract.present? && @request_kind == "prepare_round"
        compact_round_context = compact_round_context(payload, workflow_node: workflow_node)
        if compact_round_context.present?
          compact["round_context"] = compact_round_context
        else
          compact.delete("round_context")
        end
      end

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
          "control_plane",
          "agent_definition_version_id"
        )

      if compact_runtime_context.present?
        compact["runtime_context"] = compact_runtime_context
      else
        compact.delete("runtime_context")
      end

      compact
    end

    def compact_round_context(payload, workflow_node:)
      round_context = payload["round_context"]
      stored_view =
        if round_context.is_a?(Hash)
          round_context.deep_stringify_keys["work_context_view"]
        end
      stored_view ||= ProviderExecution::BuildWorkContextView.call(workflow_node: workflow_node) if workflow_node.present?
      return if stored_view.blank?

      { "work_context_view" => stored_view.deep_stringify_keys }
    end

    def resolved_workflow_node
      workflow_node_public_id = extract_task_payload(@payload)&.fetch("workflow_node_id", nil)
      return if workflow_node_public_id.blank?

      WorkflowNode.find_by!(
        installation_id: @agent_definition_version.installation_id,
        public_id: workflow_node_public_id
      )
    end

    def extract_task_payload(payload)
      task = payload["task"]
      task if task.is_a?(Hash)
    end

    def validate_task_payload!
      return unless %w[prepare_round execute_tool consult_prompt_compaction execute_prompt_compaction].include?(@request_kind)
      return if extract_task_payload(@payload).present?

      raise ArgumentError, "missing task payload for #{@request_kind}"
    end
  end
end
