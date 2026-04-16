module CoreMatrixCLI
  module CommandHelpers
    def self.included(base)
      base.class_eval do
        no_commands do
          def runtime
            @runtime ||= CoreMatrixCLI.runtime_factory.call
          end

          def orchestrator
            @orchestrator ||= SetupOrchestrator.new(runtime: runtime)
          end

          def ensure_base_url!
            return runtime.stored_base_url unless runtime.stored_base_url.to_s.strip.empty?

            runtime.persist_base_url(ask("CoreMatrix Base URL:"))
            runtime.stored_base_url
          end

          def require_base_url!
            return runtime.stored_base_url unless runtime.stored_base_url.to_s.strip.empty?

            say("base url: missing")
            nil
          end

          def login_via_prompt
            runtime.login(
              email: ask("Operator Email:"),
              password: ask("Password:", echo: false)
            )
          end

          def print_session(payload)
            say("operator email: #{payload.dig("user", "email")}")
            say("installation: #{payload.dig("installation", "name")}") if payload.dig("installation", "name")
          end

          def print_snapshot(snapshot)
            say("authenticated: #{snapshot.fetch("authenticated", false) ? "yes" : "no"}")
            say("bootstrap state: #{snapshot.fetch("bootstrap_state", "unknown")}")
            say("default workspace: #{snapshot.fetch("default_workspace", "unknown")}")
            say("workspace agent: #{snapshot.fetch("workspace_agent", "unknown")}")
            say("codex subscription: #{snapshot.fetch("codex_subscription", "unknown")}")
            say("telegram: #{snapshot.fetch("telegram", "unknown")}")
            say("weixin: #{snapshot.fetch("weixin", "unknown")}")
          end
        end
      end
    end
  end

  class AuthCLI < Thor
    include CommandHelpers

    desc "login", "Log in as an operator"
    def login
      ensure_base_url!
      payload = login_via_prompt
      orchestrator.persist_auth_payload(payload)
      print_session(payload)
    end

    desc "whoami", "Show the current operator session"
    def whoami
      return unless require_base_url!

      print_session(runtime.current_session)
    rescue HTTPClient::UnauthorizedError
      runtime.clear_session_token
      say("authenticated: no")
    end

    desc "logout", "Log out the current operator session"
    def logout
      if runtime.session_token.to_s.strip.empty?
        runtime.clear_session_token
      else
        runtime.logout
      end

      say("authenticated: no")
    end
  end

  class CodexCLI < Thor
    include CommandHelpers
    POLL_TIMEOUT = 10
    POLL_INTERVAL = 0.01

    desc "login", "Authorize the Codex subscription"
    def login
      return unless require_base_url!

      authorization = runtime.start_codex_authorization.fetch("authorization")
      authorization_url = authorization["authorization_url"]
      say("authorization url: #{authorization_url}") if authorization_url
      browser_launcher.open(authorization_url) if authorization_url

      final_payload = Polling.until(
        timeout: POLL_TIMEOUT,
        interval: POLL_INTERVAL,
        stop_on: ->(payload) { payload.dig("authorization", "status") != "pending" }
      ) do
        runtime.codex_authorization_status
      end

      say("codex subscription: #{final_payload.dig("authorization", "status")}")
    end

    desc "status", "Show the Codex authorization status"
    def status
      return unless require_base_url!

      say("codex subscription: #{runtime.codex_authorization_status.dig("authorization", "status")}")
    end

    desc "logout", "Revoke the Codex authorization"
    def logout
      return unless require_base_url!

      payload = runtime.revoke_codex_authorization
      say("codex subscription: #{payload.dig("authorization", "status")}")
    end

    no_commands do
      def browser_launcher
        @browser_launcher ||= CoreMatrixCLI.browser_launcher_factory.call
      end
    end
  end

  class ProvidersCLI < Thor
    desc "codex SUBCOMMAND", "Manage the Codex provider"
    subcommand "codex", CodexCLI
  end

  class WorkspaceCLI < Thor
    include CommandHelpers

    desc "list", "List available workspaces"
    def list
      return unless require_base_url!

      runtime.list_workspaces.fetch("workspaces", []).each do |workspace|
        marker = workspace["is_default"] ? "*" : "-"
        say("#{marker} #{workspace.fetch("workspace_id")} #{workspace.fetch("name")}")
      end
    end

    option :name, type: :string, desc: "Workspace name"
    option :privacy, type: :string, default: "private", desc: "Workspace privacy"
    option :default, type: :boolean, default: false, desc: "Mark the workspace as default"
    desc "create", "Create a workspace"
    def create
      return unless require_base_url!

      payload = runtime.create_workspace(
        name: options[:name] || ask("Workspace Name:"),
        privacy: options[:privacy],
        is_default: options[:default]
      )
      workspace = payload.fetch("workspace")
      runtime.persist_workspace_context(workspace_id: workspace.fetch("workspace_id"))
      say("selected workspace: #{workspace.fetch("workspace_id")}")
      say("workspace name: #{workspace.fetch("name")}")
    end

    desc "use WORKSPACE_ID", "Select a workspace"
    def use(workspace_id)
      runtime.persist_workspace_context(workspace_id: workspace_id)
      say("selected workspace: #{workspace_id}")
    end
  end

  class AgentCLI < Thor
    include CommandHelpers

    option :workspace_id, type: :string, desc: "Workspace public id"
    option :agent_id, type: :string, required: true, desc: "Agent public id"
    desc "attach", "Attach an agent to the selected workspace"
    def attach
      return unless require_base_url!

      workspace_id = options[:workspace_id] || runtime.config_store.read["workspace_id"]
      raise ArgumentError, "workspace_id is required" if workspace_id.to_s.strip.empty?

      payload = runtime.attach_workspace_agent(
        workspace_id: workspace_id,
        agent_id: options.fetch(:agent_id)
      )
      workspace_agent = payload.fetch("workspace_agent")
      runtime.persist_workspace_context(
        workspace_id: workspace_agent.fetch("workspace_id"),
        workspace_agent_id: workspace_agent.fetch("workspace_agent_id")
      )
      say("selected workspace agent: #{workspace_agent.fetch("workspace_agent_id")}")
    end
  end

  class TelegramCLI < Thor
    include CommandHelpers

    desc "setup", "Configure Telegram ingress"
    def setup; end
  end

  class WeixinCLI < Thor
    include CommandHelpers

    desc "setup", "Configure Weixin ingress"
    def setup; end
  end

  class IngressCLI < Thor
    desc "telegram SUBCOMMAND", "Manage Telegram ingress"
    subcommand "telegram", TelegramCLI

    desc "weixin SUBCOMMAND", "Manage Weixin ingress"
    subcommand "weixin", WeixinCLI
  end

  class CLI < Thor
    include CommandHelpers

    desc "init", "Bootstrap or continue operator setup"
    def init
      ensure_base_url!
      bootstrap_status = runtime.bootstrap_status

      payload =
        if bootstrap_status.fetch("bootstrap_state") == "unbootstrapped"
          runtime.bootstrap(
            name: ask("Installation Name:"),
            email: ask("Operator Email:"),
            password: ask("Password:", echo: false),
            password_confirmation: ask("Confirm Password:", echo: false),
            display_name: ask("Display Name:")
          )
        else
          current_session_or_login
        end

      orchestrator.persist_auth_payload(payload)
      orchestrator.prime_workspace_context! if payload["workspace"].nil? || payload["workspace_agent"].nil?

      installation_name = payload.dig("installation", "name")
      say("installation: #{installation_name}") if installation_name
      print_snapshot(orchestrator.readiness_snapshot)
    end

    desc "status", "Show installation readiness"
    def status
      return unless require_base_url!

      print_snapshot(orchestrator.readiness_snapshot)
    end

    register AuthCLI, "auth", "auth SUBCOMMAND", "Manage operator authentication"
    register ProvidersCLI, "providers", "providers SUBCOMMAND", "Manage provider setup"
    register WorkspaceCLI, "workspace", "workspace SUBCOMMAND", "Manage workspaces"
    register AgentCLI, "agent", "agent SUBCOMMAND", "Manage workspace agent attachments"
    register IngressCLI, "ingress", "ingress SUBCOMMAND", "Manage ingress integrations"

    private

    def current_session_or_login
      return login_via_prompt if runtime.session_token.to_s.strip.empty?

      runtime.current_session
    rescue HTTPClient::UnauthorizedError
      runtime.clear_session_token
      login_via_prompt
    end
  end
end
