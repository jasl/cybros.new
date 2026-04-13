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
        workspaces = AppSurface::Queries::WorkspacesForAgent.call(user: @user, agent: @agent)

        Result.new(
          agent: @agent,
          default_workspace_ref: Workspaces::ResolveDefaultReference.call(
            user: @user,
            agent: @agent,
            workspace: workspaces.find(&:is_default?)
          ),
          workspaces: workspaces
        )
      end
    end
  end
end
