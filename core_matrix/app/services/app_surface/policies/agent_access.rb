module AppSurface
  module Policies
    class AgentAccess
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
        ) && launchable?
      end

      private

      def launchable?
        @agent.current_agent_definition_version.present? &&
          @agent.default_execution_runtime.present? &&
          @agent.default_execution_runtime.current_execution_runtime_version.present?
      end
    end
  end
end
