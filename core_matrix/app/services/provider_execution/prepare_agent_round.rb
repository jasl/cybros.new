module ProviderExecution
  class PrepareAgentRound
    def self.call(...)
      new(...).call
    end

    def initialize(workflow_node:, transcript:, agent_request_exchange: nil)
      @workflow_node = workflow_node
      @workflow_run = workflow_node.workflow_run
      @agent_request_exchange = agent_request_exchange || ProviderExecution::AgentRequestExchange.new(agent_definition_version: workflow_node.turn.agent_definition_version)
      @transcript = Array(transcript).map { |entry| entry.deep_stringify_keys }
    end

    def call
      response = @agent_request_exchange.prepare_round(payload: request_payload)
      validate_response!(response)
      response
    end

    private

    def request_payload
      {
        "protocol_version" => "agent-runtime/2026-04-01",
        "request_kind" => "prepare_round",
        "task" => {
          "workflow_run_id" => @workflow_run.public_id,
          "workflow_node_id" => @workflow_node.public_id,
          "conversation_id" => @workflow_run.conversation.public_id,
          "turn_id" => @workflow_run.turn.public_id,
          "kind" => "turn_step",
        },
        "round_context" => round_context,
        "agent_context" => agent_context,
        "provider_context" => @workflow_run.execution_snapshot.provider_context,
        "workspace_agent_context" => @workflow_run.execution_snapshot.workspace_agent_context,
        "runtime_context" => {
          "control_plane" => "agent",
          "logical_work_id" => "prepare-round:#{@workflow_node.public_id}",
          "attempt_no" => 1,
          "agent_definition_version_id" => @workflow_run.turn.agent_definition_version.public_id,
          "agent_id" => @workflow_run.turn.agent_definition_version.agent.public_id,
          "user_id" => @workflow_run.conversation.workspace.user.public_id,
        },
      }
    end

    def validate_response!(response)
      raise ProviderExecution::AgentRequestExchange::ProtocolError.new(code: "invalid_prepare_round_response", message: "agent prepare_round response must include messages") unless response["messages"].is_a?(Array)
      raise ProviderExecution::AgentRequestExchange::ProtocolError.new(code: "invalid_prepare_round_response", message: "agent prepare_round response must include visible_tool_names") unless response["visible_tool_names"].is_a?(Array)
    end

    def round_context
      execution_context = @workflow_run.execution_snapshot.conversation_projection

      {
        "messages" => @transcript,
        "context_imports" => execution_context.fetch("context_imports", []),
        "projection_fingerprint" => execution_context["projection_fingerprint"],
        "work_context_view" => ProviderExecution::BuildWorkContextView.call(workflow_node: @workflow_node),
      }.compact
    end

    def agent_context
      capability_projection = @workflow_run.execution_snapshot.capability_projection

      {
        "profile_key" => capability_projection["profile_key"],
        "is_subagent" => capability_projection["is_subagent"] == true,
        "subagent_connection_id" => capability_projection["subagent_connection_id"],
        "parent_subagent_connection_id" => capability_projection["parent_subagent_connection_id"],
        "subagent_depth" => capability_projection["subagent_depth"],
        "owner_conversation_id" => capability_projection["owner_conversation_id"],
        "model_selector_hint" => capability_projection["model_selector_hint"],
        "allowed_tool_names" => Array(capability_projection.fetch("tool_surface", [])).map { |entry| entry.fetch("tool_name") }.uniq,
      }.compact
    end
  end
end
