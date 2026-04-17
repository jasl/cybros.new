require "test_helper"

class IngressWeixinCommandTest < CoreMatrixCLITestCase
  def test_weixin_setup_renders_ansi_qr_and_polls_until_connected
    api = FakeCoreMatrixAPI.new
    api.create_ingress_binding_responses["weixin"] = {
      "ingress_binding" => {
        "ingress_binding_id" => "ib_wx_123",
      },
    }
    api.weixin_start_login_response = {
      "weixin" => {
        "login_state" => "pending",
      },
    }
    api.weixin_login_status_sequence = [
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
    config_repository = CoreMatrixCLI::State::ConfigRepository.new(path: tmp_path("config.json"))
    config_repository.write(
      "base_url" => "https://core.example.com",
      "workspace_agent_id" => "wa_123"
    )
    qr_renderer = FakeQrRenderer.new(output: "\e[qr]")

    output = run_cli(
      "ingress", "weixin", "setup",
      api: api,
      config_repository: config_repository,
      qr_renderer: qr_renderer
    )

    assert_includes output, "\e[qr]"
    assert_includes output, "connected"
    assert_equal ["weixin://scan-123"], qr_renderer.rendered_inputs
    assert_equal "ib_wx_123", config_repository.read.fetch("weixin_ingress_binding_id")
  end

  def test_weixin_help_explains_qr_behavior
    output = run_cli("ingress", "weixin", "help", "setup")

    assert_includes output, "cmctl ingress weixin setup"
    assert_includes output, "render ANSI QR"
    assert_includes output, "qr_code_url"
  end
end
