require "test_helper"

class BrowserLauncherTest < CoreMatrixCLITestCase
  def test_open_returns_false_without_invoking_shell_when_browser_is_disabled
    launcher = CoreMatrixCLI::Support::BrowserLauncher.new(
      shell_runner: ->(*) { raise "should not launch browser" }
    )

    with_env("CORE_MATRIX_CLI_DISABLE_BROWSER" => "1") do
      assert_equal false, launcher.open("https://example.test/device")
    end
  end

  def test_open_invokes_platform_browser_command_when_enabled
    commands = []
    launcher = CoreMatrixCLI::Support::BrowserLauncher.new(
      shell_runner: ->(*command) { commands << command; true },
      platform: "x86_64-linux"
    )

    assert_equal true, launcher.open("https://example.test/device")
    assert_equal [["xdg-open", "https://example.test/device"]], commands
  end
end
