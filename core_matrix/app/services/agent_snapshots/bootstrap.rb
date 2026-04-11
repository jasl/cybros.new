require "securerandom"

module AgentSnapshots
  class Bootstrap
    Result = Struct.new(:conversation, :turn, :workflow_run, keyword_init: true)

    def self.call(...)
      new(...).call
    end

    def initialize(agent_snapshot:, workspace:, manifest_snapshot: {})
      @agent_snapshot = agent_snapshot
      @workspace = workspace
      @manifest_snapshot = manifest_snapshot
    end

    def call
      raise ArgumentError, "workspace must belong to the same installation" unless same_installation?

      ApplicationRecord.transaction do
        conversation = Conversations::CreateAutomationRoot.call(
          workspace: @workspace,
          agent: @agent_snapshot.agent
        )
        turn = Turns::StartAutomationTurn.call(
          conversation: conversation,
          origin_kind: "system_internal",
          origin_payload: {
            "trigger" => "agent_snapshot_bootstrap",
            "bootstrap_manifest_snapshot" => @manifest_snapshot,
          },
          source_ref_type: "AgentSnapshot",
          source_ref_id: @agent_snapshot.public_id,
          idempotency_key: "agent_snapshot-bootstrap-#{@agent_snapshot.id}-#{SecureRandom.hex(8)}",
          external_event_key: "agent_snapshot-bootstrap-#{@agent_snapshot.id}-#{SecureRandom.hex(8)}",
          execution_runtime: @agent_snapshot.agent.default_execution_runtime,
          resolved_config_snapshot: {},
          resolved_model_selection_snapshot: {}
        )
        workflow_run = Workflows::CreateForTurn.call(
          turn: turn,
          root_node_key: "agent_snapshot_bootstrap",
          root_node_type: "agent_snapshot_bootstrap",
          decision_source: "system",
          metadata: {
            "bootstrap_manifest_snapshot" => @manifest_snapshot,
          }
        )

        AuditLog.record!(
          installation: @agent_snapshot.installation,
          action: "agent_snapshot.bootstrap_started",
          subject: @agent_snapshot,
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
      @workspace.installation_id == @agent_snapshot.installation_id
    end
  end
end
