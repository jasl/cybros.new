require "test_helper"

class CoreMatrixCLIFullSetupContractTest < CoreMatrixCLITestCase
  def test_full_setup_contract_bootstraps_authorizes_and_configures_im_paths
    server = FakeCoreMatrixServer.new do |state|
      state.bootstrap_state = "unbootstrapped"
      state.codex_authorization_status_sequence = %w[pending authorized]
      state.weixin_status_sequence = [
        { "login_state" => "pending" },
        { "login_state" => "pending", "qr_text" => "weixin://qr-login-token" },
        { "login_state" => "connected", "account_id" => "wx-123" },
      ]
    end

    server.start

    config_store = CoreMatrixCLI::ConfigStore.new(path: tmp_path("config.json"))
    credential_store = CoreMatrixCLI::CredentialStores::FileStore.new(path: tmp_path("credentials.json"))
    browser_launcher = FakeBrowserLauncher.new

    with_runtime_factory(
      lambda do
        CoreMatrixCLI::Runtime.new(
          config_store: config_store,
          credential_store: credential_store
        )
      end
    ) do
      with_browser_launcher_factory(browser_launcher) do
        output = []
        output << run_cli("init", input: "#{server.base_url}\nPrimary Installation\nadmin@example.com\nPassword123!\nPassword123!\nPrimary Admin\n", runtime: CoreMatrixCLI.runtime_factory.call, browser_launcher: browser_launcher)
        output << run_cli("providers", "codex", "login", runtime: CoreMatrixCLI.runtime_factory.call, browser_launcher: browser_launcher)
        output << run_cli("ingress", "telegram", "setup", input: "123:abc\nhttps://bot.example.com\n", runtime: CoreMatrixCLI.runtime_factory.call, browser_launcher: browser_launcher)
        output << run_cli("ingress", "weixin", "setup", runtime: CoreMatrixCLI.runtime_factory.call, browser_launcher: browser_launcher)
        output << run_cli("status", runtime: CoreMatrixCLI.runtime_factory.call, browser_launcher: browser_launcher)

        combined_output = output.join("\n")

        assert_includes combined_output, "authorized"
        assert_includes combined_output, "connected"
        assert_includes combined_output, "selected workspace: ws_contract_123 (Primary Workspace)"
        assert_includes combined_output, "selected workspace agent: wa_contract_123 (active)"
        assert_includes combined_output, "telegram: configured"
        assert_includes combined_output, "weixin: connected"
        assert_equal "sess_contract_123", credential_store.read.fetch("session_token")
        assert_equal "https://bot.example.com", server.state.telegram_connector_payload.dig("config_payload", "webhook_base_url")
        assert_equal "123:abc", server.state.telegram_connector_payload.dig("credential_ref_payload", "bot_token")
        assert_includes server.state.authorized_request_tokens, "sess_contract_123"
      end
    end
  ensure
    server&.shutdown
  end
end
