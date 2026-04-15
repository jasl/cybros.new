module Workspaces
  class ResolveDefaultReference
    Result = Struct.new(
      :state,
      :workspace,
      :workspace_id,
      :workspace_agent_id,
      :agent_id,
      :user_id,
      :name,
      :privacy,
      :default_execution_runtime_id,
      keyword_init: true
    ) do
      def materialized? = state == "materialized"

      def virtual? = state == "virtual"
    end

    def self.call(...)
      new(...).call
    end

    def initialize(user:, agent:, workspace: nil, name: CreateDefault::DEFAULT_NAME)
      @user = user
      @agent = agent
      @workspace = workspace
      @name = name
    end

    def call
      workspace = @workspace || materialized_workspace
      workspace_agent = resolve_workspace_agent(workspace)
      return nil if workspace.blank? || workspace_agent.blank?

      Result.new(
        state: "materialized",
        workspace: workspace,
        workspace_id: workspace.public_id,
        workspace_agent_id: workspace_agent.public_id,
        agent_id: @agent.public_id,
        user_id: @user.public_id,
        name: workspace.name,
        privacy: workspace.privacy,
        default_execution_runtime_id: workspace_agent.default_execution_runtime&.public_id || @agent.default_execution_runtime&.public_id
      )
    end

    private

    def materialized_workspace
      Workspace
        .joins(:workspace_agents)
        .where(
          installation_id: @user.installation_id,
          user: @user,
          is_default: true,
          workspace_agents: {
            agent_id: @agent.id,
            lifecycle_state: "active",
          }
        )
        .includes(workspace_agents: :default_execution_runtime)
        .distinct
        .first
    end

    def resolve_workspace_agent(workspace)
      return nil if workspace.blank?

      if workspace.association(:workspace_agents).loaded?
        workspace.workspace_agents.find { |workspace_agent| workspace_agent.agent_id == @agent.id && workspace_agent.active? }
      else
        workspace.workspace_agents.where(agent: @agent, lifecycle_state: "active").order(:id).first
      end
    end
  end
end
