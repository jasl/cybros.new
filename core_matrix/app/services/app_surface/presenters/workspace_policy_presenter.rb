module AppSurface
  module Presenters
    class WorkspacePolicyPresenter
      def self.call(...)
        new(...).call
      end

      def initialize(workspace:, workspace_agent:)
        @workspace = workspace
        @workspace_agent = workspace_agent
      end

      def call
        agent = @workspace_agent.agent
        available = agent.present? ? WorkspacePolicies::Capabilities.available_for(agent: agent) : []
        disabled = WorkspacePolicies::Capabilities.disabled_for(workspace: @workspace, workspace_agent: @workspace_agent) & available
        effective = agent.present? ? WorkspacePolicies::Capabilities.effective_for(workspace: @workspace, workspace_agent: @workspace_agent) : []
        features = WorkspaceFeatures::Resolver.call(workspace: @workspace)

        {
          "workspace_id" => @workspace.public_id,
          "workspace_agent_id" => @workspace_agent.public_id,
          "agent_id" => agent&.public_id,
          "default_execution_runtime_id" => @workspace_agent.default_execution_runtime&.public_id,
          "features" => features,
          "available_capabilities" => available,
          "disabled_capabilities" => disabled,
          "effective_capabilities" => effective,
        }
      end
    end
  end
end
