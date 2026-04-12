module AppSurface
  module Queries
    class AgentHome
      Result = Struct.new(:agent, :default_workspace_ref, :workspaces, keyword_init: true)

      def self.call(...)
        new(...).call
      end

      def initialize(user:, agent:)
        @user = user
        @agent = agent
      end

      def call
        Result.new(
          agent: @agent,
          default_workspace_ref: Workspaces::ResolveDefaultReference.call(user: @user, agent: @agent),
          workspaces: AppSurface::Queries::WorkspacesForAgent.call(user: @user, agent: @agent)
        )
      end
    end
  end
end
