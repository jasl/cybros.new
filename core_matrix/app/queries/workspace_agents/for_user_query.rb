module WorkspaceAgents
  class ForUserQuery
    def self.call(...)
      new(...).call
    end

    def initialize(user:, workspace: nil, agent: nil, launchable_only: false)
      @user = user
      @workspace = workspace
      @agent = agent
      @launchable_only = launchable_only
    end

    def call
      scope = WorkspaceAgent
        .joins(:workspace)
        .where(
          installation_id: @user.installation_id,
          workspaces: {
            user_id: @user.id,
            privacy: "private",
          }
        )
        .includes(:agent, :default_execution_runtime, :workspace)

      scope = scope.where(workspace: @workspace) if @workspace.present?
      scope = scope.where(agent: @agent) if @agent.present?
      scope = scope.where(lifecycle_state: "active") if @launchable_only

      scope.order(created_at: :asc, id: :asc).to_a
    end
  end
end
