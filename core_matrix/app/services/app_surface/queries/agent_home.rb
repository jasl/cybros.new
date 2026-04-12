module AppSurface
  module Queries
    class AgentHome
      Result = Struct.new(:agent, :default_workspace_ref, :workspaces, keyword_init: true)

      def self.call(...)
        new(...).call
      end

      def initialize(user:, agent:)
        @user = user
        @agent = agent
      end

      def call
        binding = existing_or_virtual_binding

        Result.new(
          agent: @agent,
          default_workspace_ref: Workspaces::BuildDefaultReference.call(user_agent_binding: binding),
          workspaces: AppSurface::Queries::WorkspacesForAgent.call(user: @user, agent: @agent)
        )
      end

      private

      def existing_or_virtual_binding
        UserAgentBinding.find_by(
          installation: @user.installation,
          user: @user,
          agent: @agent
        ) || UserAgentBinding.new(
          installation: @user.installation,
          user: @user,
          agent: @agent,
          preferences: {}
        )
      end
    end
  end
end
