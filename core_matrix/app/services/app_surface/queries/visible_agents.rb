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
      end
    end
  end
end
