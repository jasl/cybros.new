module CoreMatrixCLI
  module UseCases
    class ShowStatus < Base
      def call
        snapshot = {
          "authenticated" => false,
          "bootstrap_state" => "unknown",
          "installation_default_workspace" => "missing",
          "selected_workspace" => nil,
          "selected_workspace_agent" => nil,
          "codex_subscription" => "unknown",
          "telegram" => "unknown",
          "telegram_webhook" => "unknown",
          "weixin" => "unknown",
        }

        return snapshot if stored_base_url.to_s.strip.empty?

        bootstrap = api.bootstrap_status
        snapshot["bootstrap_state"] = bootstrap.fetch("bootstrap_state", "unknown")
        snapshot["installation_name"] = bootstrap.dig("installation", "name")

        return snapshot if stored_session_token.to_s.strip.empty?

        current_session_payload = authenticated_api.current_session
        snapshot["authenticated"] = current_session_payload.dig("user", "email").to_s.strip != ""
        persist_operator_email(current_session_payload.dig("user", "email")) if snapshot["authenticated"]

        workspaces_payload = authenticated_api.list_workspaces.fetch("workspaces", [])
        snapshot["installation_default_workspace"] = workspaces_payload.any? { |workspace| workspace["is_default"] } ? "present" : "missing"

        selected_workspace = select_workspace(workspaces_payload)
        selected_workspace_agent = select_workspace_agent(selected_workspace)
        snapshot["selected_workspace"] = selected_workspace.slice("workspace_id", "name", "is_default") if selected_workspace
        snapshot["selected_workspace_agent"] = selected_workspace_agent.slice("workspace_agent_id", "lifecycle_state") if selected_workspace_agent

        llm_provider = authenticated_api.provider_status("codex_subscription").fetch("llm_provider", {})
        snapshot["codex_subscription"] =
          if llm_provider["reauthorization_required"]
            "reauthorization_required"
          elsif llm_provider["usable"]
            "authorized"
          elsif llm_provider["configured"]
            "configured"
          else
            "missing"
          end

        workspace_agent_id = selected_workspace_agent&.dig("workspace_agent_id") || config_payload["workspace_agent_id"]

        telegram_binding_id = stored_ingress_binding_id("telegram")
        if workspace_agent_id.to_s.strip != "" && telegram_binding_id.to_s.strip != ""
          telegram_binding = authenticated_api.show_ingress_binding(
            workspace_agent_id: workspace_agent_id,
            ingress_binding_id: telegram_binding_id
          ).fetch("ingress_binding", {})
          snapshot["telegram"] = telegram_binding.dig("channel_connector", "configured") ? "configured" : "missing"
        end

        telegram_webhook_binding_id = stored_ingress_binding_id("telegram_webhook")
        if workspace_agent_id.to_s.strip != "" && telegram_webhook_binding_id.to_s.strip != ""
          telegram_webhook_binding = authenticated_api.show_ingress_binding(
            workspace_agent_id: workspace_agent_id,
            ingress_binding_id: telegram_webhook_binding_id
          ).fetch("ingress_binding", {})
          snapshot["telegram_webhook"] = telegram_webhook_binding.dig("channel_connector", "configured") ? "configured" : "missing"
        end

        weixin_binding_id = stored_ingress_binding_id("weixin")
        if workspace_agent_id.to_s.strip != "" && weixin_binding_id.to_s.strip != ""
          snapshot["weixin"] = authenticated_api.weixin_login_status(
            workspace_agent_id: workspace_agent_id,
            ingress_binding_id: weixin_binding_id
          ).dig("weixin", "login_state") || "unknown"
        end

        snapshot
      rescue Errors::UnauthorizedError
        clear_session_token
        snapshot
      rescue Errors::NotFoundError
        snapshot
      end
    end
  end
end
