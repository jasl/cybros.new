require "securerandom"

module AgentProgramVersions
  class Bootstrap
    Result = Struct.new(:conversation, :turn, :workflow_run, keyword_init: true)

    def self.call(...)
      new(...).call
    end

    def initialize(deployment:, workspace:, manifest_snapshot: {})
      @deployment = deployment
      @workspace = workspace
      @manifest_snapshot = manifest_snapshot
    end

    def call
      raise ArgumentError, "workspace must belong to the same installation" unless same_installation?

      ApplicationRecord.transaction do
        conversation = Conversations::CreateAutomationRoot.call(
          workspace: @workspace,
          agent_program: @deployment.agent_program
        )
        turn = Turns::StartAutomationTurn.call(
          conversation: conversation,
          origin_kind: "system_internal",
          origin_payload: {
            "trigger" => "deployment_bootstrap",
            "bootstrap_manifest_snapshot" => @manifest_snapshot,
          },
          source_ref_type: "AgentProgramVersion",
          source_ref_id: @deployment.public_id,
          idempotency_key: "deployment-bootstrap-#{@deployment.id}-#{SecureRandom.hex(8)}",
          external_event_key: "deployment-bootstrap-#{@deployment.id}-#{SecureRandom.hex(8)}",
          execution_runtime: @deployment.agent_program.default_execution_runtime,
          resolved_config_snapshot: {},
          resolved_model_selection_snapshot: {}
        )
        workflow_run = Workflows::CreateForTurn.call(
          turn: turn,
          root_node_key: "deployment_bootstrap",
          root_node_type: "deployment_bootstrap",
          decision_source: "system",
          metadata: {
            "bootstrap_manifest_snapshot" => @manifest_snapshot,
          }
        )

        AuditLog.record!(
          installation: @deployment.installation,
          action: "agent_program_version.bootstrap_started",
          subject: @deployment,
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
      @workspace.installation_id == @deployment.installation_id
    end
  end
end
