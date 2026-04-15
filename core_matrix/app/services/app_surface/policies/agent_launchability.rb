module AppSurface
  module Policies
    class AgentLaunchability
      DEFAULT_RUNTIME = Object.new.freeze

      def self.call(...)
        new(...).call
      end

      def initialize(user:, agent:, workspace_agent: nil, execution_runtime: DEFAULT_RUNTIME)
        @user = user
        @agent = agent
        @workspace_agent = workspace_agent
        @execution_runtime = execution_runtime
      end

      def call
        AgentVisibility.call(user: @user, agent: @agent) && launchable?
      end

      private

      def launchable?
        runtime =
          if @execution_runtime.equal?(DEFAULT_RUNTIME)
            @workspace_agent&.default_execution_runtime || @agent.default_execution_runtime
          else
            @execution_runtime
          end

        @agent.current_agent_definition_version.present? &&
          runtime.present? &&
          runtime.current_execution_runtime_version.present?
      end
    end
  end
end
