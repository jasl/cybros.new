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
          .where(
            installation: @user.installation,
            user: @user,
            agent: @agent,
            privacy: "private"
          )
          .includes(:agent, :default_execution_runtime)
          .order(is_default: :desc, name: :asc, id: :asc)
          .to_a
          .select { |workspace| AppSurface::Policies::WorkspaceAccess.call(user: @user, workspace: workspace) }
      end
    end
  end
end
