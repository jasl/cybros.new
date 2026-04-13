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

    def initialize(user:, agent:, name: CreateDefault::DEFAULT_NAME)
      @user = user
      @agent = agent
      @name = name
    end

    def call
      Workspaces::ResolveDefaultReference.call(
        user: @user,
        agent: @agent,
        name: @name
      )
    end
  end
end
