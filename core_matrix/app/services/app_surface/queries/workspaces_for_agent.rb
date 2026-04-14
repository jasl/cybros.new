module AppSurface
  module Queries
    class WorkspacesForAgent
      def self.call(...)
        new(...).call
      end

      def initialize(user:, agent:)
        @user = user
        @agent = agent
      end

      def call
        Workspace
          .accessible_to_user(@user)
          .eager_load(workspace_agents: :default_execution_runtime)
          .where(
            workspace_agents: {
              agent_id: @agent.id,
              lifecycle_state: "active",
            }
          )
          .distinct
          .order(is_default: :desc, name: :asc, id: :asc)
          .to_a
      end
    end
  end
end
