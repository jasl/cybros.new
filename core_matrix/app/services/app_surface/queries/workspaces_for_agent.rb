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
          .where(agent: @agent)
          .includes(:agent, :default_execution_runtime)
          .order(is_default: :desc, name: :asc, id: :asc)
          .to_a
      end
    end
  end
end
