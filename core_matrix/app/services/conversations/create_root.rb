module Conversations
  class CreateRoot
    include Conversations::CreationSupport

    def self.call(...)
      new(...).call
    end

    def initialize(workspace_agent: nil, workspace: nil, agent: nil, purpose: "interactive", execution_runtime: nil)
      @workspace_agent = workspace_agent || resolve_workspace_agent!(workspace:, agent:)
      @workspace = workspace || @workspace_agent.workspace
      @agent = agent || @workspace_agent.agent
      @purpose = purpose
      @execution_runtime = execution_runtime

      raise ArgumentError, "workspace must match workspace_agent" if @workspace != @workspace_agent.workspace
      raise ArgumentError, "agent must match workspace_agent" if @agent != @workspace_agent.agent
    end

    def call
      ApplicationRecord.transaction do
        create_root_conversation!(
          workspace_agent: @workspace_agent,
          workspace: @workspace,
          agent: @agent,
          purpose: @purpose,
          execution_runtime: @execution_runtime
        )
      end
    end

    private

    def resolve_workspace_agent!(workspace:, agent:)
      raise ArgumentError, "workspace_agent or workspace is required" if workspace.blank?

      scope = workspace.workspace_agents.where(lifecycle_state: "active")
      scope = scope.where(agent: agent) if agent.present?
      matches = scope.order(:id).limit(2).to_a

      if matches.empty?
        raise ArgumentError, "workspace must have an active workspace_agent#{agent.present? ? ' for the requested agent' : ''}"
      end

      if agent.blank? && matches.size > 1
        raise ArgumentError, "workspace_agent is required when workspace has multiple active mounts"
      end

      matches.first
    end
  end
end
