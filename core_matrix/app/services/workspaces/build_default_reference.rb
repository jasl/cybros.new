module Workspaces
  class BuildDefaultReference
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

    def initialize(user_agent_binding:, name: CreateDefault::DEFAULT_NAME)
      @user_agent_binding = user_agent_binding
      @name = name
    end

    def call
      workspace = Workspace.find_by(user_agent_binding: @user_agent_binding, is_default: true)

      Result.new(
        state: workspace.present? ? "materialized" : "virtual",
        workspace: workspace,
        workspace_id: workspace&.public_id,
        agent_id: @user_agent_binding.agent.public_id,
        user_id: @user_agent_binding.user.public_id,
        name: workspace&.name || @name,
        privacy: workspace&.privacy || "private",
        default_execution_runtime_id: workspace&.default_execution_runtime&.public_id || @user_agent_binding.agent.default_execution_runtime&.public_id
      )
    end
  end
end
