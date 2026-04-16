module CoreMatrixCLI
  class Runtime
    def initialize(config_store: ConfigStore.new, credential_store: CredentialStore.new, client_class: HTTPClient)
      @config_store = config_store
      @credential_store = credential_store
      @client_class = client_class
    end

    attr_reader :config_store, :credential_store

    def stored_base_url
      config_store.read["base_url"]
    end

    def session_token
      credential_store.read["session_token"]
    end

    def persist_base_url(base_url)
      config_store.merge("base_url" => normalize_base_url(base_url))
    end

    def persist_session_token(session_token)
      credential_store.write("session_token" => session_token)
    end

    def clear_session_token
      credential_store.clear
    end

    def persist_operator_email(email)
      config_store.merge("operator_email" => email)
    end

    def persist_workspace_context(workspace_id: nil, workspace_agent_id: nil)
      current_payload = config_store.read
      next_payload = current_payload.dup

      workspace_changed =
        workspace_id && workspace_id != current_payload["workspace_id"]
      workspace_agent_changed =
        workspace_agent_id && workspace_agent_id != current_payload["workspace_agent_id"]

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

      config_store.write(next_payload) if next_payload != current_payload
    end

    def stored_ingress_binding_id(platform)
      config_store.read["#{platform}_ingress_binding_id"]
    end

    def persist_ingress_binding_id(platform, ingress_binding_id)
      config_store.merge("#{platform}_ingress_binding_id" => ingress_binding_id)
    end

    def bootstrap_status
      public_client.get("/app_api/bootstrap/status")
    end

    def bootstrap(attributes)
      public_client.post("/app_api/bootstrap", body: attributes)
    end

    def login(email:, password:)
      public_client.post(
        "/app_api/session",
        body: {
          email: email,
          password: password,
        }
      )
    end

    def current_session
      authenticated_client.get("/app_api/session")
    end

    def logout
      authenticated_client.delete("/app_api/session")
    ensure
      clear_session_token
    end

    def installation_status
      authenticated_client.get("/app_api/admin/installation")
    end

    def list_workspaces
      authenticated_client.get("/app_api/workspaces")
    end

    def create_workspace(name:, privacy: "private", is_default: false)
      authenticated_client.post(
        "/app_api/workspaces",
        body: {
          name: name,
          privacy: privacy,
          is_default: is_default,
        }
      )
    end

    def list_agents
      authenticated_client.get("/app_api/agents")
    end

    def attach_workspace_agent(workspace_id:, agent_id:)
      authenticated_client.post(
        "/app_api/workspaces/#{workspace_id}/workspace_agents",
        body: { agent_id: agent_id }
      )
    end

    def provider_status(provider_handle)
      authenticated_client.get("/app_api/admin/llm_providers/#{provider_handle}")
    end

    def start_codex_authorization
      authenticated_client.post("/app_api/admin/llm_providers/codex_subscription/authorization")
    end

    def codex_authorization_status
      authenticated_client.get("/app_api/admin/llm_providers/codex_subscription/authorization")
    end

    def revoke_codex_authorization
      authenticated_client.delete("/app_api/admin/llm_providers/codex_subscription/authorization")
    end

    def create_ingress_binding(workspace_agent_id:, platform:)
      authenticated_client.post(
        "/app_api/workspace_agents/#{workspace_agent_id}/ingress_bindings",
        body: { platform: platform }
      )
    end

    def update_ingress_binding(workspace_agent_id:, ingress_binding_id:, channel_connector:, reissue_setup_secret: false)
      authenticated_client.patch(
        "/app_api/workspace_agents/#{workspace_agent_id}/ingress_bindings/#{ingress_binding_id}",
        body: {
          channel_connector: channel_connector,
          reissue_setup_secret: reissue_setup_secret,
        }
      )
    end

    def show_ingress_binding(workspace_agent_id:, ingress_binding_id:)
      authenticated_client.get(
        "/app_api/workspace_agents/#{workspace_agent_id}/ingress_bindings/#{ingress_binding_id}"
      )
    end

    def start_weixin_login(workspace_agent_id:, ingress_binding_id:)
      authenticated_client.post(
        "/app_api/workspace_agents/#{workspace_agent_id}/ingress_bindings/#{ingress_binding_id}/weixin/start_login"
      )
    end

    def weixin_login_status(workspace_agent_id:, ingress_binding_id:)
      authenticated_client.get(
        "/app_api/workspace_agents/#{workspace_agent_id}/ingress_bindings/#{ingress_binding_id}/weixin/login_status"
      )
    end

    def readiness_snapshot
      snapshot = {
        "authenticated" => false,
        "bootstrap_state" => "unknown",
        "installation_default_workspace" => "missing",
        "selected_workspace" => nil,
        "selected_workspace_agent" => nil,
        "codex_subscription" => "unknown",
        "telegram" => "unknown",
        "weixin" => "unknown",
      }

      return snapshot unless stored_base_url

      bootstrap = bootstrap_status
      snapshot["bootstrap_state"] = bootstrap.fetch("bootstrap_state", "unknown")
      snapshot["installation_name"] = bootstrap.dig("installation", "name")

      return snapshot if session_token.to_s.strip.empty?

      current_session_payload = current_session
      snapshot["authenticated"] = current_session_payload.dig("user", "email").to_s.strip != ""
      persist_operator_email(current_session_payload.dig("user", "email")) if snapshot["authenticated"]

      workspaces_payload = list_workspaces.fetch("workspaces", [])
      snapshot["installation_default_workspace"] = workspaces_payload.any? { |workspace| workspace["is_default"] } ? "present" : "missing"

      selected_workspace = select_workspace(workspaces_payload)
      selected_workspace_agent = select_workspace_agent(selected_workspace)
      snapshot["selected_workspace"] = selected_workspace.slice("workspace_id", "name", "is_default") if selected_workspace
      snapshot["selected_workspace_agent"] = selected_workspace_agent.slice("workspace_agent_id", "lifecycle_state") if selected_workspace_agent

      llm_provider = provider_status("codex_subscription").fetch("llm_provider", {})
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

      workspace_agent_id = selected_workspace_agent&.dig("workspace_agent_id") || config_store.read["workspace_agent_id"]
      telegram_binding_id = stored_ingress_binding_id("telegram")
      if workspace_agent_id.to_s.strip != "" && telegram_binding_id.to_s.strip != ""
        telegram_binding = show_ingress_binding(
          workspace_agent_id: workspace_agent_id,
          ingress_binding_id: telegram_binding_id
        ).fetch("ingress_binding", {})
        snapshot["telegram"] = telegram_binding.dig("channel_connector", "configured") ? "configured" : "missing"
      end

      weixin_binding_id = stored_ingress_binding_id("weixin")
      if workspace_agent_id.to_s.strip != "" && weixin_binding_id.to_s.strip != ""
        snapshot["weixin"] = weixin_login_status(
          workspace_agent_id: workspace_agent_id,
          ingress_binding_id: weixin_binding_id
        ).dig("weixin", "login_state") || "unknown"
      end

      snapshot
    rescue HTTPClient::UnauthorizedError
      clear_session_token
      snapshot
    rescue HTTPClient::NotFoundError
      snapshot
    end

    private

    def public_client
      @client_class.new(base_url: required_base_url)
    end

    def authenticated_client
      @client_class.new(base_url: required_base_url, session_token: session_token)
    end

    def required_base_url
      stored_base_url || raise(ArgumentError, "base_url is not configured")
    end

    def normalize_base_url(base_url)
      base_url.to_s.strip.sub(%r{/+\z}, "")
    end

    def select_workspace(workspaces_payload)
      workspace_id = config_store.read["workspace_id"]

      workspaces_payload.find { |workspace| workspace["workspace_id"] == workspace_id } ||
        workspaces_payload.find { |workspace| workspace["is_default"] } ||
        workspaces_payload.first
    end

    def select_workspace_agent(workspace_payload)
      return nil if workspace_payload.nil?

      workspace_agent_id = config_store.read["workspace_agent_id"]
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
      payload.delete("weixin_ingress_binding_id")
    end
  end
end
