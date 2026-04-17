module CoreMatrixCLI
  module UseCases
    class RunInit < Base
      def call(base_url:, ask:, ask_secret:)
        normalized_base_url = persist_base_url(base_url)
        bootstrap_status = api(base_url: normalized_base_url).bootstrap_status
        orchestrator = build_setup_orchestrator

        payload =
          if bootstrap_status.fetch("bootstrap_state") == "unbootstrapped"
            api(base_url: normalized_base_url).bootstrap(
              name: ask.call("Installation Name:"),
              email: ask.call("Operator Email:"),
              password: ask_secret.call("Password:"),
              password_confirmation: ask_secret.call("Confirm Password:"),
              display_name: ask.call("Display Name:")
            )
          else
            current_session_or_login(base_url: normalized_base_url, ask: ask, ask_secret: ask_secret)
          end

        orchestrator.persist_auth_payload(payload)
        if payload["workspace"].nil? || payload["workspace_agent"].nil?
          orchestrator.prime_workspace_context!
        end

        {
          payload: payload,
          snapshot: orchestrator.readiness_snapshot,
        }
      end

      private

      def build_setup_orchestrator
        SetupOrchestrator.new(
          config_repository: config_repository,
          credential_repository: credential_repository,
          api_factory: api_factory,
          browser_launcher: browser_launcher,
          qr_renderer: qr_renderer,
          polling: polling,
          time_source: time_source
        )
      end

      def current_session_or_login(base_url:, ask:, ask_secret:)
        return login(base_url: base_url, ask: ask, ask_secret: ask_secret) if stored_session_token.to_s.strip.empty?

        api(base_url: base_url, session_token: stored_session_token).current_session
      rescue Errors::UnauthorizedError
        clear_session_token
        login(base_url: base_url, ask: ask, ask_secret: ask_secret)
      end

      def login(base_url:, ask:, ask_secret:)
        api(base_url: base_url).login(
          email: ask.call("Operator Email:"),
          password: ask_secret.call("Password:")
        )
      end
    end
  end
end
