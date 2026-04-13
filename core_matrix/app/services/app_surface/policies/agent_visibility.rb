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
        return false if @user.blank? || @agent.blank?

        Agent.visible_to_user(@user).where(id: @agent.id).exists?
      end
    end
  end
end
