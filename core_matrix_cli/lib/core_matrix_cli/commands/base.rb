require "thor"

module CoreMatrixCLI
  module Commands
    class Base < Thor
      remove_command :tree

      def self.exit_on_failure?
        false
      end

      no_commands do
        def config_repository
          @config_repository ||= CoreMatrixCLI.config_repository_factory.call
        end

        def credential_repository
          @credential_repository ||= CoreMatrixCLI.credential_repository_factory.call
        end

        def browser_launcher
          @browser_launcher ||= CoreMatrixCLI.browser_launcher_factory.call
        end

        def qr_renderer
          @qr_renderer ||= CoreMatrixCLI.qr_renderer_factory.call
        end

        def build_use_case(klass)
          klass.new(
            config_repository: config_repository,
            credential_repository: credential_repository,
            api_factory: CoreMatrixCLI.api_factory,
            browser_launcher: browser_launcher,
            qr_renderer: qr_renderer,
            polling: CoreMatrixCLI::Support::Polling,
            time_source: -> { Time.now }
          )
        end

        def with_cli_errors
          yield
        rescue Errors::UnauthorizedError
          credential_repository.clear
          say("Session expired or revoked.")
          say("Run `cmctl auth login` to authenticate again.")
        rescue Errors::TransportError => error
          say("Could not reach CoreMatrix: #{error.message}")
        rescue Errors::UnprocessableEntityError => error
          say("Request rejected: #{error_message_from(error)}")
        rescue Errors::NotFoundError => error
          say("Requested resource was not found: #{error_message_from(error)}")
        rescue Errors::ServerError => error
          say("CoreMatrix returned an error: #{error_message_from(error)}")
        rescue ArgumentError => error
          say(error.message)
        end

        def print_session(payload)
          say("Authenticated as: #{payload.dig("user", "email")}")
          say("Installation: #{payload.dig("installation", "name")}") if payload.dig("installation", "name")
        end

        def print_snapshot(snapshot)
          say("Base URL: #{config_repository.read["base_url"]}") if config_repository.read["base_url"].to_s.strip != ""
          say("Installation: #{snapshot.fetch("installation_name")}") if snapshot["installation_name"]
          say("authenticated: #{snapshot.fetch("authenticated", false) ? "yes" : "no"}")
          say("bootstrap state: #{snapshot.fetch("bootstrap_state", "unknown")}")
          say("installation default workspace: #{snapshot.fetch("installation_default_workspace", "unknown")}")

          selected_workspace = snapshot["selected_workspace"]
          if selected_workspace
            say("selected workspace: #{selected_workspace.fetch("workspace_id")} (#{selected_workspace.fetch("name")})")
          else
            say("selected workspace: missing")
          end

          selected_workspace_agent = snapshot["selected_workspace_agent"]
          if selected_workspace_agent
            say(
              "selected workspace agent: " \
              "#{selected_workspace_agent.fetch("workspace_agent_id")} " \
              "(#{selected_workspace_agent.fetch("lifecycle_state")})"
            )
          else
            say("selected workspace agent: missing")
          end

          say("codex subscription: #{snapshot.fetch("codex_subscription", "unknown")}")
          say("telegram: #{snapshot.fetch("telegram", "unknown")}")
          say("telegram webhook: #{snapshot.fetch("telegram_webhook", "unknown")}")
          say("weixin: #{snapshot.fetch("weixin", "unknown")}")
        end

        def print_codex_authorization(authorization)
          say("codex subscription: #{authorization.fetch("status")}")
          return unless authorization["status"] == "pending"

          verification_uri = authorization["verification_uri"]
          user_code = authorization["user_code"]
          expires_at = authorization["expires_at"]

          say("Verification URL:") if verification_uri
          say(verification_uri) if verification_uri
          say("User code: #{user_code}") if user_code
          say("Expires at: #{expires_at}") if expires_at
        end

        def require_base_url!
          return config_repository.read["base_url"] unless config_repository.read["base_url"].to_s.strip.empty?

          say("No CoreMatrix base URL is configured.")
          say("Run `cmctl init` or `cmctl auth login` first.")
          nil
        end

        def selected_workspace_id
          workspace_id = config_repository.read["workspace_id"]
          if workspace_id.to_s.strip.empty?
            say("No workspace is selected.")
            say("Run `cmctl workspace create` or `cmctl workspace use <workspace_id>` first.")
            return nil
          end

          workspace_id
        end

        def selected_workspace_agent_id!
          workspace_agent_id = config_repository.read["workspace_agent_id"]
          if workspace_agent_id.to_s.strip.empty?
            say("No workspace agent is selected.")
            say("Run `cmctl agent attach` after choosing or creating a workspace.")
            return nil
          end

          workspace_agent_id
        end

        def error_message_from(error)
          error.payload.is_a?(Hash) ? error.payload["error"] || error.message : error.message
        end

        def prompt_secret(prompt)
          ask(prompt, echo: false)
        rescue Errno::ENOTTY
          ask(prompt)
        end
      end
    end
  end
end
