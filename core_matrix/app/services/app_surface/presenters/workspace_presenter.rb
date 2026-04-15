module AppSurface
  module Presenters
    class WorkspacePresenter
      def self.call(...)
        new(...).call
      end

      def initialize(workspace:, agent_public_id: nil, workspace_agents: nil)
        @workspace = workspace
        @agent_public_id = agent_public_id
        @workspace_agents = workspace_agents
      end

      def call
        {
          "workspace_id" => @workspace.public_id,
          "agent_id" => @agent_public_id,
          "default_execution_runtime_id" => default_execution_runtime_id,
          "name" => @workspace.name,
          "privacy" => @workspace.privacy,
          "is_default" => @workspace.is_default,
          "workspace_agents" => presented_workspace_agents,
          "created_at" => @workspace.created_at&.iso8601(6),
          "updated_at" => @workspace.updated_at&.iso8601(6),
        }.compact
      end

      private

      def presented_workspace_agents
        resolved_workspace_agents.map do |workspace_agent|
          WorkspaceAgentPresenter.call(workspace_agent: workspace_agent)
        end
      end

      def resolved_workspace_agents
        workspace_agents =
          if @workspace_agents.present?
            Array(@workspace_agents)
          elsif @workspace.association(:workspace_agents).loaded?
            @workspace.workspace_agents
          else
            @workspace.workspace_agents.includes(:agent, :default_execution_runtime).to_a
          end

        if @agent_public_id.present?
          workspace_agents.select { |workspace_agent| workspace_agent.agent.public_id == @agent_public_id }
        else
          workspace_agents
        end.sort_by(&:id)
      end

      def default_execution_runtime_id
        return nil unless @agent_public_id.present?

        resolved_workspace_agents.first&.default_execution_runtime&.public_id
      end
    end
  end
end
