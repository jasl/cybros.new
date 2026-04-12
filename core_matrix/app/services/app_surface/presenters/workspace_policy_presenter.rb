module AppSurface
  module Presenters
    class WorkspacePolicyPresenter
      def self.call(...)
        new(...).call
      end

      def initialize(workspace:)
        @workspace = workspace
      end

      def call
        available = WorkspacePolicies::Capabilities.available_for(agent: @workspace.user_agent_binding.agent)
        disabled = WorkspacePolicies::Capabilities.disabled_for(workspace: @workspace) & available
        effective = WorkspacePolicies::Capabilities.effective_for(workspace: @workspace)

        {
          "workspace_id" => @workspace.public_id,
          "agent_id" => @workspace.user_agent_binding.agent.public_id,
          "default_execution_runtime_id" => @workspace.default_execution_runtime&.public_id,
          "available_capabilities" => available,
          "disabled_capabilities" => disabled,
          "effective_capabilities" => effective,
        }
      end
    end
  end
end
