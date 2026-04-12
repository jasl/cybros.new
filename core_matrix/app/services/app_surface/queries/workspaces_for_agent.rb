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
        binding = UserAgentBinding.find_by(
          installation: @user.installation,
          user: @user,
          agent: @agent
        )
        return [] if binding.blank?

        Workspace
          .where(
            installation: @user.installation,
            user: @user,
            user_agent_binding: binding,
            privacy: "private"
          )
          .includes(:default_execution_runtime, user_agent_binding: :agent)
          .order(is_default: :desc, name: :asc, id: :asc)
          .to_a
          .select { |workspace| AppSurface::Policies::WorkspaceAccess.call(user: @user, workspace: workspace) }
      end
    end
  end
end
