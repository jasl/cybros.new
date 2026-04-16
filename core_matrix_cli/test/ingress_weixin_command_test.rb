require "test_helper"

class CoreMatrixCLIWeixinCommandTest < CoreMatrixCLITestCase
  def test_weixin_setup_renders_ansi_qr_and_polls_until_connected
    runtime = FakeRuntime.new(
      config_store: CoreMatrixCLI::ConfigStore.new(path: tmp_path("config.json")),
      credential_store: CoreMatrixCLI::CredentialStores::FileStore.new(path: tmp_path("credentials.json"))
    )
    runtime.persist_base_url("https://core.example.com")
    runtime.persist_workspace_context(workspace_agent_id: "wa_123")
    runtime.create_ingress_binding_responses["weixin"] = {
      "ingress_binding" => {
        "ingress_binding_id" => "ib_wx_123",
      },
    }
    runtime.weixin_start_login_response = {
      "weixin" => {
        "login_state" => "pending",
      },
    }
    runtime.weixin_login_status_sequence = [
      {
        "weixin" => {
          "login_state" => "pending",
          "qr_text" => "weixin://scan-123",
        },
      },
      {
        "weixin" => {
          "login_state" => "connected",
        },
      },
    ]

    output = run_cli("ingress", "weixin", "setup", runtime: runtime)

    assert_includes output, "\e["
    assert_includes output, "connected"
    assert_equal "ib_wx_123", runtime.config_store.read.fetch("weixin_ingress_binding_id")
  end

  def test_weixin_help_explains_qr_behavior
    runtime = FakeRuntime.new(
      config_store: CoreMatrixCLI::ConfigStore.new(path: tmp_path("config.json")),
      credential_store: CoreMatrixCLI::CredentialStores::FileStore.new(path: tmp_path("credentials.json"))
    )

    output = run_cli("ingress", "weixin", "help", "setup", runtime: runtime)

    assert_includes output, "render ANSI QR"
    assert_includes output, "qr_code_url"
  end
end
