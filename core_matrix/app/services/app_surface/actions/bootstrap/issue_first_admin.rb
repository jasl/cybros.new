module AppSurface
  module Actions
    module Bootstrap
      class IssueFirstAdmin
        SESSION_TTL = 30.days

        def self.call(...)
          new(...).call
        end

        def initialize(name:, email:, password:, password_confirmation:, display_name:, session_expires_at: SESSION_TTL.from_now)
          @name = name
          @email = email
          @password = password
          @password_confirmation = password_confirmation
          @display_name = display_name
          @session_expires_at = session_expires_at
        end

        def call
          bootstrap = Installations::BootstrapFirstAdmin.call(
            name: @name,
            email: @email,
            password: @password,
            password_confirmation: @password_confirmation,
            display_name: @display_name
          )

          session = Session.issue_for!(
            identity: bootstrap.identity,
            user: bootstrap.user,
            expires_at: @session_expires_at,
            metadata: {}
          )

          workspace = bootstrap.user.workspaces.includes(workspace_agents: [:agent, :default_execution_runtime]).find_by(is_default: true)

          {
            installation: bootstrap.installation,
            user: bootstrap.user,
            session: session,
            session_token: session.plaintext_token,
            workspace: workspace,
            workspace_agent: workspace&.primary_workspace_agent,
          }
        end
      end
    end
  end
end
