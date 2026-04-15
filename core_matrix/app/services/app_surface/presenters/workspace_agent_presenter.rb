module AppSurface
  module Presenters
    class WorkspaceAgentPresenter
      def self.call(...)
        new(...).call
      end

      def initialize(workspace_agent:)
        @workspace_agent = workspace_agent
      end

      def call
        {
          "workspace_agent_id" => @workspace_agent.public_id,
          "workspace_id" => @workspace_agent.workspace.public_id,
          "agent_id" => @workspace_agent.agent.public_id,
          "lifecycle_state" => @workspace_agent.lifecycle_state,
          "default_execution_runtime_id" => @workspace_agent.default_execution_runtime&.public_id,
          "global_instructions" => @workspace_agent.global_instructions,
          "revoked_reason_kind" => @workspace_agent.revoked_reason_kind,
          "revoked_at" => @workspace_agent.revoked_at&.iso8601(6),
          "capability_policy_payload" => @workspace_agent.capability_policy_payload || {},
          "entry_policy_payload" => @workspace_agent.entry_policy_payload || {},
        }.compact
      end
    end
  end
end
