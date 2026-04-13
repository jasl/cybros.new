module Workspaces
  class ResolveDefaultReference
    Result = Struct.new(
      :state,
      :workspace,
      :workspace_id,
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
      workspace = @workspace || Workspace.find_by(
        installation_id: @user.installation_id,
        user: @user,
        agent: @agent,
        is_default: true
      )

      Result.new(
        state: workspace.present? ? "materialized" : "virtual",
        workspace: workspace,
        workspace_id: workspace&.public_id,
        agent_id: @agent.public_id,
        user_id: @user.public_id,
        name: workspace&.name || @name,
        privacy: workspace&.privacy || "private",
        default_execution_runtime_id: workspace&.default_execution_runtime&.public_id || @agent.default_execution_runtime&.public_id
      )
    end
  end
end
