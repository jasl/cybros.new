module CoreMatrixCLI
  module CommandHelpers
    def self.included(base)
      base.class_eval do
        no_commands do
          def with_cli_errors
            yield
          rescue HTTPClient::UnauthorizedError
            runtime.clear_session_token
            say("Session expired or revoked.")
            say("Run `cmctl auth login` to authenticate again.")
          rescue HTTPClient::TransportError => error
            say("Could not reach CoreMatrix: #{error.message}")
          rescue HTTPClient::UnprocessableEntityError => error
            say("Request rejected: #{error_message_from(error)}")
          rescue HTTPClient::NotFoundError => error
            say("Requested resource was not found: #{error_message_from(error)}")
          rescue HTTPClient::ServerError => error
            say("CoreMatrix returned an error: #{error_message_from(error)}")
          rescue ArgumentError => error
            say(error.message)
          end

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

            say("No CoreMatrix base URL is configured.")
            say("Run `cmctl init` or `cmctl auth login` first.")
            nil
          end

          def login_via_prompt
            runtime.login(
              email: ask("Operator Email:"),
              password: ask("Password:", echo: false)
            )
          end

          def print_session(payload)
            say("Authenticated as: #{payload.dig("user", "email")}")
            say("Installation: #{payload.dig("installation", "name")}") if payload.dig("installation", "name")
          end

          def print_snapshot(snapshot)
            say("Base URL: #{runtime.stored_base_url}") if runtime.stored_base_url.to_s.strip != ""
            say("Installation: #{snapshot.fetch("installation_name")}") if snapshot["installation_name"]
            say("authenticated: #{snapshot.fetch("authenticated", false) ? "yes" : "no"}")
            say("bootstrap state: #{snapshot.fetch("bootstrap_state", "unknown")}")
            say("default workspace: #{snapshot.fetch("default_workspace", "unknown")}")
            say("workspace agent: #{snapshot.fetch("workspace_agent", "unknown")}")
            say("codex subscription: #{snapshot.fetch("codex_subscription", "unknown")}")
            say("telegram: #{snapshot.fetch("telegram", "unknown")}")
            say("weixin: #{snapshot.fetch("weixin", "unknown")}")
          end

          def selected_workspace_agent_id!
            workspace_agent_id = runtime.config_store.read["workspace_agent_id"]
            if workspace_agent_id.to_s.strip.empty?
              say("No workspace agent is selected.")
              say("Run `cmctl agent attach` after choosing or creating a workspace.")
              return nil
            end

            workspace_agent_id
          end

          def selected_workspace_id
            workspace_id = runtime.config_store.read["workspace_id"]
            if workspace_id.to_s.strip.empty?
              say("No workspace is selected.")
              say("Run `cmctl workspace create` or `cmctl workspace use <workspace_id>` first.")
              return nil
            end

            workspace_id
          end

          def normalize_base_url(base_url)
            base_url.to_s.strip.sub(%r{/+\z}, "")
          end

          def error_message_from(error)
            error.payload.is_a?(Hash) ? error.payload["error"] || error.message : error.message
          end
        end
      end
    end
  end

  class AuthCLI < Thor
    include CommandHelpers
    remove_command :tree

    def self.banner(command, *_args)
      "cmctl auth #{command.usage}"
    end

    desc "login", "Log in as an operator"
    def login
      with_cli_errors do
        ensure_base_url!
        payload = login_via_prompt
        orchestrator.persist_auth_payload(payload)
        print_session(payload)
      end
    end

    desc "whoami", "Show the current operator session"
    def whoami
      with_cli_errors do
        return unless require_base_url!

        print_session(runtime.current_session)
      end
    end

    desc "logout", "Log out the current operator session"
    def logout
      with_cli_errors do
        if runtime.session_token.to_s.strip.empty?
          runtime.clear_session_token
        else
          runtime.logout
        end

        say("Authenticated: no")
      end
    end
  end

  class CodexCLI < Thor
    include CommandHelpers
    remove_command :tree
    POLL_TIMEOUT = 10
    POLL_INTERVAL = 0.01

    def self.banner(command, *_args)
      "cmctl providers codex #{command.usage}"
    end

    desc "login", "Authorize the Codex subscription"
    def login
      with_cli_errors do
        return unless require_base_url!

        authorization = runtime.start_codex_authorization.fetch("authorization")
        authorization_url = authorization["authorization_url"]
        if authorization_url
          browser_launcher.open(authorization_url)
          say("Open this URL if the browser does not launch:")
          say(authorization_url)
        end

        final_payload = Polling.until(
          timeout: POLL_TIMEOUT,
          interval: POLL_INTERVAL,
          stop_on: ->(payload) { payload.dig("authorization", "status") != "pending" }
        ) do
          runtime.codex_authorization_status
        end

        say("codex subscription: #{final_payload.dig("authorization", "status")}")
      end
    end

    desc "status", "Show the Codex authorization status"
    def status
      with_cli_errors do
        return unless require_base_url!

        say("codex subscription: #{runtime.codex_authorization_status.dig("authorization", "status")}")
      end
    end

    desc "logout", "Revoke the Codex authorization"
    def logout
      with_cli_errors do
        return unless require_base_url!

        payload = runtime.revoke_codex_authorization
        say("codex subscription: #{payload.dig("authorization", "status")}")
      end
    end

    no_commands do
      def browser_launcher
        @browser_launcher ||= CoreMatrixCLI.browser_launcher_factory.call
      end
    end
  end

  class ProvidersCLI < Thor
    remove_command :tree

    def self.banner(command, *_args)
      "cmctl providers #{command.usage}"
    end

    desc "codex SUBCOMMAND", "Manage the Codex provider"
    subcommand "codex", CodexCLI
  end

  class WorkspaceCLI < Thor
    include CommandHelpers
    remove_command :tree

    def self.banner(command, *_args)
      "cmctl workspace #{command.usage}"
    end

    desc "list", "List available workspaces"
    def list
      with_cli_errors do
        return unless require_base_url!

        runtime.list_workspaces.fetch("workspaces", []).each do |workspace|
          marker = workspace["is_default"] ? "*" : "-"
          say("#{marker} #{workspace.fetch("workspace_id")} #{workspace.fetch("name")}")
        end
      end
    end

    option :name, type: :string, desc: "Workspace name"
    option :privacy, type: :string, default: "private", desc: "Workspace privacy"
    option :default, type: :boolean, default: false, desc: "Mark the workspace as default"
    desc "create", "Create a workspace"
    def create
      with_cli_errors do
        return unless require_base_url!

        payload = runtime.create_workspace(
          name: options[:name] || ask("Workspace Name:"),
          privacy: options[:privacy],
          is_default: options[:default]
        )
        workspace = payload.fetch("workspace")
        runtime.persist_workspace_context(workspace_id: workspace.fetch("workspace_id"))
        say("Selected workspace: #{workspace.fetch("workspace_id")}")
        say("Workspace name: #{workspace.fetch("name")}")
      end
    end

    desc "use WORKSPACE_ID", "Select a workspace"
    def use(workspace_id)
      with_cli_errors do
        runtime.persist_workspace_context(workspace_id: workspace_id)
        say("Selected workspace: #{workspace_id}")
      end
    end
  end

  class AgentCLI < Thor
    include CommandHelpers
    remove_command :tree

    def self.banner(command, *_args)
      "cmctl agent #{command.usage}"
    end

    option :workspace_id, type: :string, desc: "Workspace public id"
    option :agent_id, type: :string, required: true, desc: "Agent public id"
    desc "attach", "Attach an agent to the selected workspace"
    def attach
      with_cli_errors do
        return unless require_base_url!

        workspace_id = options[:workspace_id] || selected_workspace_id
        return if workspace_id.nil?

        payload = runtime.attach_workspace_agent(
          workspace_id: workspace_id,
          agent_id: options.fetch(:agent_id)
        )
        workspace_agent = payload.fetch("workspace_agent")
        runtime.persist_workspace_context(
          workspace_id: workspace_agent.fetch("workspace_id"),
          workspace_agent_id: workspace_agent.fetch("workspace_agent_id")
        )
        say("Selected workspace agent: #{workspace_agent.fetch("workspace_agent_id")}")
      end
    end
  end

  class TelegramCLI < Thor
    include CommandHelpers
    remove_command :tree

    def self.banner(command, *_args)
      "cmctl ingress telegram #{command.usage}"
    end

    long_desc <<~HELP
      Preparation:
        - Create a bot in BotFather
        - Copy the bot token
        - Prepare a public HTTPS base URL for CoreMatrix

      This command will ask for:
        - bot token
        - webhook base URL

      This command will print:
        - webhook URL
        - webhook secret header name
        - webhook secret token

      v1 verification boundary:
        - API-contract only, not real webhook delivery
    HELP
    desc "setup", "Configure Telegram ingress"
    def setup
      with_cli_errors do
        return unless require_base_url!

        workspace_agent_id = selected_workspace_agent_id!
        return if workspace_agent_id.nil?

        ingress_binding_id = runtime.stored_ingress_binding_id("telegram")

        if ingress_binding_id.to_s.strip.empty?
          created_binding = runtime.create_ingress_binding(
            workspace_agent_id: workspace_agent_id,
            platform: "telegram"
          ).fetch("ingress_binding")
          ingress_binding_id = created_binding.fetch("ingress_binding_id")
          runtime.persist_ingress_binding_id("telegram", ingress_binding_id)
        end

        bot_token = ask("Telegram Bot Token:")
        webhook_base_url = normalize_base_url(ask("Webhook Base URL:"))

        updated_binding = runtime.update_ingress_binding(
          workspace_agent_id: workspace_agent_id,
          ingress_binding_id: ingress_binding_id,
          channel_connector: {
            credential_ref_payload: {
              bot_token: bot_token,
            },
            config_payload: {
              webhook_base_url: webhook_base_url,
            },
          }
        ).fetch("ingress_binding")

        setup = updated_binding.fetch("setup")
        webhook_url = "#{webhook_base_url}#{setup.fetch("webhook_path")}"

        say("Webhook URL: #{webhook_url}")
        say("Webhook Secret Header: X-Telegram-Bot-Api-Secret-Token")
        say("Webhook Secret Token: #{setup.fetch("webhook_secret_token")}")
        say("Next: register the webhook URL and secret token with Telegram.")
      end
    end
  end

  class WeixinCLI < Thor
    include CommandHelpers
    remove_command :tree

    def self.banner(command, *_args)
      "cmctl ingress weixin #{command.usage}"
    end

    long_desc <<~HELP
      Preparation:
        - Ensure you are logged in
        - Ensure a workspace and workspace agent are selected
        - Use a terminal that can render ANSI QR output if possible

      This command will:
        - create or reuse the binding
        - start login when needed
        - poll status
        - render ANSI QR from qr_text when available
        - print qr_code_url only as a fallback

      v1 verification boundary:
        - API-contract only, not real account scanning or live message delivery
    HELP
    desc "setup", "Configure Weixin ingress"
    def setup
      with_cli_errors do
        return unless require_base_url!

        workspace_agent_id = selected_workspace_agent_id!
        return if workspace_agent_id.nil?

        ingress_binding_id = runtime.stored_ingress_binding_id("weixin")

        if ingress_binding_id.to_s.strip.empty?
          created_binding = runtime.create_ingress_binding(
            workspace_agent_id: workspace_agent_id,
            platform: "weixin"
          ).fetch("ingress_binding")
          ingress_binding_id = created_binding.fetch("ingress_binding_id")
          runtime.persist_ingress_binding_id("weixin", ingress_binding_id)
        end

        runtime.start_weixin_login(
          workspace_agent_id: workspace_agent_id,
          ingress_binding_id: ingress_binding_id
        )

        final_payload = poll_weixin_status(workspace_agent_id: workspace_agent_id, ingress_binding_id: ingress_binding_id)
        say("weixin status: #{final_payload.dig("weixin", "login_state")}")
      end
    end

    no_commands do
      def ansi_qr_renderer
        @ansi_qr_renderer ||= AnsiQRRenderer.new
      end

      def poll_weixin_status(workspace_agent_id:, ingress_binding_id:)
        last_qr_text = nil
        last_qr_code_url = nil

        Polling.until(
          timeout: CodexCLI::POLL_TIMEOUT,
          interval: CodexCLI::POLL_INTERVAL,
          stop_on: ->(payload) { payload.dig("weixin", "login_state") != "pending" }
        ) do
          payload = runtime.weixin_login_status(
            workspace_agent_id: workspace_agent_id,
            ingress_binding_id: ingress_binding_id
          )
          qr_text = payload.dig("weixin", "qr_text")
          qr_code_url = payload.dig("weixin", "qr_code_url")

          if qr_text && qr_text != last_qr_text
            say(ansi_qr_renderer.render(qr_text))
            last_qr_text = qr_text
          elsif qr_code_url && qr_code_url != last_qr_code_url
            say("QR Code URL: #{qr_code_url}")
            last_qr_code_url = qr_code_url
          end

          payload
        end
      end
    end
  end

  class IngressCLI < Thor
    remove_command :tree

    def self.banner(command, *_args)
      "cmctl ingress #{command.usage}"
    end

    desc "telegram SUBCOMMAND", "Manage Telegram ingress"
    subcommand "telegram", TelegramCLI

    desc "weixin SUBCOMMAND", "Manage Weixin ingress"
    subcommand "weixin", WeixinCLI
  end

  class CLI < Thor
    include CommandHelpers
    remove_command :tree

    desc "init", "Bootstrap or continue operator setup"
    def init
      with_cli_errors do
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
        say("Installation: #{installation_name}") if installation_name
        print_snapshot(orchestrator.readiness_snapshot)
      end
    end

    desc "status", "Show installation readiness"
    def status
      with_cli_errors do
        return unless require_base_url!

        print_snapshot(orchestrator.readiness_snapshot)
      end
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
