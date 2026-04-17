require "test_helper"

class StatusCommandTest < CoreMatrixCLITestCase
  def test_status_reads_live_snapshot_and_prints_codex_state
    api = FakeCoreMatrixAPI.new
    api.bootstrap_status_payload = {
      "bootstrap_state" => "bootstrapped",
      "installation" => { "name" => "Primary Installation" },
    }
    api.session_response = {
      "user" => {
        "email" => "admin@example.com",
      },
    }
    api.workspaces_response = {
      "workspaces" => [
        {
          "workspace_id" => "ws_123",
          "name" => "CLI Workspace",
          "is_default" => true,
          "workspace_agents" => [
            {
              "workspace_agent_id" => "wa_123",
              "lifecycle_state" => "active",
            },
          ],
        },
      ],
    }
    api.provider_status_responses["codex_subscription"] = {
      "llm_provider" => {
        "usable" => true,
        "configured" => true,
      },
    }
    api.show_ingress_binding_responses["ib_tg_123"] = {
      "ingress_binding" => { "channel_connector" => { "configured" => true } },
    }
    api.show_ingress_binding_responses["ib_tgwh_123"] = {
      "ingress_binding" => { "channel_connector" => { "configured" => true } },
    }
    api.weixin_login_status_sequence = [
      { "weixin" => { "login_state" => "connected" } },
    ]
    config_repository = CoreMatrixCLI::State::ConfigRepository.new(path: tmp_path("config.json"))
    credential_repository = CoreMatrixCLI::CredentialStores::FileStore.new(path: tmp_path("credentials.json"))
    config_repository.write(
      "base_url" => "https://core.example.com",
      "workspace_id" => "ws_123",
      "workspace_agent_id" => "wa_123",
      "telegram_ingress_binding_id" => "ib_tg_123",
      "telegram_webhook_ingress_binding_id" => "ib_tgwh_123",
      "weixin_ingress_binding_id" => "ib_wx_123"
    )
    credential_repository.write("session_token" => "sess_123")

    output = run_cli(
      "status",
      api: api,
      config_repository: config_repository,
      credential_repository: credential_repository
    )

    assert_includes output, "Base URL: https://core.example.com"
    assert_includes output, "Installation: Primary Installation"
    assert_includes output, "installation default workspace: present"
    assert_includes output, "selected workspace: ws_123 (CLI Workspace)"
    assert_includes output, "selected workspace agent: wa_123 (active)"
    assert_includes output, "codex subscription: authorized"
    assert_includes output, "telegram: configured"
    assert_includes output, "telegram webhook: configured"
    assert_includes output, "weixin: connected"
    assert_includes api.calls, [:bootstrap_status]
  end

  def test_status_explains_how_to_configure_base_url_when_missing
    output = run_cli("status")

    assert_includes output, "No CoreMatrix base URL is configured."
    assert_includes output, "cmctl init"
  end
end
