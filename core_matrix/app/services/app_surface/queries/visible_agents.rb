module AppSurface
  module Queries
    class VisibleAgents
      def self.call(...)
        new(...).call
      end

      def initialize(user:)
        @user = user
      end

      def call
        Agents::VisibleToUserQuery.call(user: @user)
          .select { |agent| AppSurface::Policies::AgentVisibility.call(user: @user, agent: agent) }
      end
    end
  end
end
