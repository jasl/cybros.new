require "securerandom"

module AgentDefinitionVersions
  class Bootstrap
    Result = Struct.new(:conversation, :turn, :workflow_run, keyword_init: true)

    def self.call(...)
      new(...).call
    end

    def initialize(agent_definition_version:, workspace:, manifest_snapshot: {})
      @agent_definition_version = agent_definition_version
      @workspace = workspace
      @manifest_snapshot = manifest_snapshot
    end

    def call
      raise ArgumentError, "workspace must belong to the same installation" unless same_installation?

      ApplicationRecord.transaction do
        conversation = Conversations::CreateAutomationRoot.call(
          workspace: @workspace,
          agent: @agent_definition_version.agent
        )
        turn = Turns::StartAutomationTurn.call(
          conversation: conversation,
          origin_kind: "system_internal",
          origin_payload: {
            "trigger" => "agent_definition_version_bootstrap",
            "bootstrap_manifest_snapshot" => @manifest_snapshot,
          },
          source_ref_type: "AgentDefinitionVersion",
          source_ref_id: @agent_definition_version.public_id,
          idempotency_key: "agent-definition-version-bootstrap-#{@agent_definition_version.id}-#{SecureRandom.hex(8)}",
          external_event_key: "agent-definition-version-bootstrap-#{@agent_definition_version.id}-#{SecureRandom.hex(8)}",
          execution_runtime: @agent_definition_version.agent.default_execution_runtime,
          resolved_config_snapshot: {},
          resolved_model_selection_snapshot: {}
        )
        workflow_run = Workflows::CreateForTurn.call(
          turn: turn,
          root_node_key: "agent_definition_version_bootstrap",
          root_node_type: "agent_definition_version_bootstrap",
          decision_source: "system",
          metadata: {
            "bootstrap_manifest_snapshot" => @manifest_snapshot,
          }
        )

        AuditLog.record!(
          installation: @agent_definition_version.installation,
          action: "agent_definition_version.bootstrap_started",
          subject: @agent_definition_version,
          metadata: {
            "conversation_id" => conversation.id,
            "turn_id" => turn.id,
            "workflow_run_id" => workflow_run.id,
          }
        )

        Result.new(conversation: conversation, turn: turn, workflow_run: workflow_run)
      end
    end

    private

    def same_installation?
      @workspace.installation_id == @agent_definition_version.installation_id
    end
  end
end
