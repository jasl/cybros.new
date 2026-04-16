module AppSurface
  module Presenters
    class AuthenticatedSessionPresenter
      def self.call(...)
        new(...).call
      end

      def initialize(session:, plaintext_token: nil, workspace: nil, workspace_agent: nil)
        @session = session
        @plaintext_token = plaintext_token
        @workspace = workspace
        @workspace_agent = workspace_agent
      end

      def call
        {
          "user" => present_user,
          "installation" => present_installation,
          "session" => present_session,
          "session_token" => @plaintext_token,
          "workspace" => present_workspace,
          "workspace_agent" => present_workspace_agent,
        }.compact
      end

      private

      def present_user
        user = @session.user

        {
          "user_id" => user.public_id,
          "display_name" => user.display_name,
          "role" => user.role,
          "email" => user.identity.email,
        }
      end

      def present_installation
        installation = @session.user.installation

        {
          "name" => installation.name,
          "bootstrap_state" => installation.bootstrap_state,
        }
      end

      def present_session
        {
          "session_id" => @session.public_id,
          "expires_at" => @session.expires_at.iso8601(6),
        }
      end

      def present_workspace
        return nil if @workspace.blank?

        WorkspacePresenter.call(workspace: @workspace, workspace_agents: Array(@workspace_agent || @workspace.primary_workspace_agent).compact)
      end

      def present_workspace_agent
        return nil if @workspace_agent.blank?

        WorkspaceAgentPresenter.call(workspace_agent: @workspace_agent)
      end
    end
  end
end
