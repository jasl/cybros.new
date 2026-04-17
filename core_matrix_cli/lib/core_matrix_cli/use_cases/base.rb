module CoreMatrixCLI
  module UseCases
    class Base
      def initialize(config_repository:, credential_repository:, api_factory:, browser_launcher: nil, qr_renderer: nil, polling: CoreMatrixCLI::Support::Polling, time_source: -> { Time.now })
        @config_repository = config_repository
        @credential_repository = credential_repository
        @api_factory = api_factory
        @browser_launcher = browser_launcher
        @qr_renderer = qr_renderer
        @polling = polling
        @time_source = time_source
      end

      private

      attr_reader :config_repository, :credential_repository, :api_factory,
        :browser_launcher, :qr_renderer, :polling, :time_source

      def config_payload
        config_repository.read
      end

      def stored_base_url
        config_payload["base_url"]
      end

      def stored_session_token
        credential_repository.read["session_token"]
      end

      def api(base_url: stored_base_url, session_token: nil)
        api_factory.call(base_url: base_url, session_token: session_token)
      end

      def authenticated_api
        api(session_token: stored_session_token)
      end

      def persist_base_url(base_url)
        normalized = normalize_base_url(base_url)
        config_repository.merge("base_url" => normalized)
        normalized
      end

      def persist_session_token(session_token)
        return if session_token.to_s.strip.empty?

        credential_repository.write("session_token" => session_token)
      end

      def clear_session_token
        credential_repository.clear
      end

      def persist_operator_email(email)
        return if email.to_s.strip.empty?

        config_repository.merge("operator_email" => email)
      end

      def persist_auth_payload(payload)
        persist_session_token(payload["session_token"])
        persist_operator_email(payload.dig("user", "email"))
      end

      def persist_workspace_context(workspace_id: nil, workspace_agent_id: nil)
        current_payload = config_payload
        next_payload = current_payload.dup

        workspace_changed = workspace_id && workspace_id != current_payload["workspace_id"]
        workspace_agent_changed = workspace_agent_id && workspace_agent_id != current_payload["workspace_agent_id"]

        if workspace_changed
          next_payload["workspace_id"] = workspace_id
          next_payload.delete("workspace_agent_id")
          clear_ingress_binding_selection!(next_payload)
        elsif workspace_id
          next_payload["workspace_id"] = workspace_id
        end

        if workspace_agent_changed
          next_payload["workspace_agent_id"] = workspace_agent_id
          clear_ingress_binding_selection!(next_payload)
        elsif workspace_agent_id
          next_payload["workspace_agent_id"] = workspace_agent_id
        end

        config_repository.write(next_payload) if next_payload != current_payload
      end

      def stored_ingress_binding_id(platform)
        config_payload["#{platform}_ingress_binding_id"]
      end

      def persist_ingress_binding_id(platform, ingress_binding_id)
        config_repository.merge("#{platform}_ingress_binding_id" => ingress_binding_id)
      end

      def select_workspace(workspaces_payload)
        workspace_id = config_payload["workspace_id"]

        workspaces_payload.find { |workspace| workspace["workspace_id"] == workspace_id } ||
          workspaces_payload.find { |workspace| workspace["is_default"] } ||
          workspaces_payload.first
      end

      def select_workspace_agent(workspace_payload)
        return nil if workspace_payload.nil?

        workspace_agent_id = config_payload["workspace_agent_id"]
        workspace_agents = Array(workspace_payload["workspace_agents"])

        selected_workspace_agent = workspace_agents.find do |workspace_agent|
          workspace_agent["workspace_agent_id"] == workspace_agent_id
        end
        return selected_workspace_agent if active_workspace_agent?(selected_workspace_agent)

        workspace_agents.find { |workspace_agent| active_workspace_agent?(workspace_agent) }
      end

      def active_workspace_agent?(workspace_agent_payload)
        workspace_agent_payload && workspace_agent_payload["lifecycle_state"] == "active"
      end

      def clear_ingress_binding_selection!(payload)
        payload.delete("telegram_ingress_binding_id")
        payload.delete("telegram_webhook_ingress_binding_id")
        payload.delete("weixin_ingress_binding_id")
      end

      def normalize_base_url(base_url)
        base_url.to_s.strip.sub(%r{/+\z}, "")
      end
    end
  end
end
