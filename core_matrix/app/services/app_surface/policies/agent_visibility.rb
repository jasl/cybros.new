module AppSurface
  module Policies
    class AgentVisibility
      def self.call(...)
        new(...).call
      end

      def initialize(user:, agent:)
        @user = user
        @agent = agent
      end

      def call
        ResourceVisibility::Usability.agent_usable_by_user?(
          user: @user,
          agent: @agent
        )
      end
    end
  end
end
