require "test_helper"
require "open3"
require_relative "support/fake_core_matrix_server"

class FullSetupContractTest < CoreMatrixCLITestCase
  def test_full_setup_contract_bootstraps_authorizes_and_configures_im_paths
    server = FakeCoreMatrixServer.new do |state|
      state.bootstrap_state = "unbootstrapped"
      state.codex_authorization_status_sequence = %w[authorized]
      state.codex_authorization_poll_sequence = %w[pending authorized]
      state.weixin_status_sequence = [
        { "login_state" => "pending" },
        { "login_state" => "pending", "qr_text" => "weixin://qr-login-token" },
        { "login_state" => "connected", "account_id" => "wx-123" },
      ]
    end

    server.start

    cli_root = File.expand_path("..", __dir__)
    config_path = tmp_path("config.json")
    credential_path = tmp_path("credentials.json")
    env = {
      "BUNDLE_GEMFILE" => File.join(cli_root, "Gemfile"),
      "CORE_MATRIX_CLI_CONFIG_PATH" => config_path,
      "CORE_MATRIX_CLI_CREDENTIAL_PATH" => credential_path,
      "CORE_MATRIX_CLI_CREDENTIAL_STORE" => "file",
      "CORE_MATRIX_CLI_DISABLE_BROWSER" => "1",
    }

    output = []
    output << run_executable(env, cli_root, "init", stdin_data: "#{server.base_url}\nPrimary Installation\nadmin@example.com\nPassword123!\nPassword123!\nPrimary Admin\n")
    output << run_executable(env, cli_root, "providers", "codex", "login")
    output << run_executable(env, cli_root, "ingress", "telegram", "setup", stdin_data: "123:abc\n")
    output << run_executable(env, cli_root, "ingress", "telegram-webhook", "setup", stdin_data: "456:def\nhttps://bot.example.com\n")
    output << run_executable(env, cli_root, "ingress", "weixin", "setup")
    output << run_executable(env, cli_root, "status")

    combined_output = output.join("\n")
    config_payload = JSON.parse(File.read(config_path))
    credential_payload = JSON.parse(File.read(credential_path))

    assert_includes combined_output, "authorized"
    assert_includes combined_output, "connected"
    assert_includes combined_output, "selected workspace: ws_contract_123 (Primary Workspace)"
    assert_includes combined_output, "selected workspace agent: wa_contract_123 (active)"
    assert_includes combined_output, "telegram: configured"
    assert_includes combined_output, "telegram webhook: configured"
    assert_includes combined_output, "weixin: connected"
    assert_equal "sess_contract_123", credential_payload.fetch("session_token")
    assert_equal "wa_contract_123", config_payload.fetch("workspace_agent_id")
    assert_nil server.state.connector_payload_for("telegram").dig("config_payload", "webhook_base_url")
    assert_equal "123:abc", server.state.connector_payload_for("telegram").dig("credential_ref_payload", "bot_token")
    assert_equal "https://bot.example.com", server.state.connector_payload_for("telegram_webhook").dig("config_payload", "webhook_base_url")
    assert_equal "456:def", server.state.connector_payload_for("telegram_webhook").dig("credential_ref_payload", "bot_token")
    assert_includes server.state.authorized_request_tokens, "sess_contract_123"
  ensure
    server&.shutdown
  end

  private

  def run_executable(env, cli_root, *args, stdin_data: "")
    stdout, stderr, status = Open3.capture3(
      env,
      "bundle", "exec", "./exe/cmctl", *args,
      stdin_data: stdin_data,
      chdir: cli_root
    )

    assert status.success?, "expected #{args.join(" ")} to pass, stderr=#{stderr}"

    stdout
  end
end
