module AppSurface
  module Queries
    class AgentHome
      Result = Struct.new(:agent, :workspaces, keyword_init: true)

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
          workspaces: workspaces
        )
      end
    end
  end
end
