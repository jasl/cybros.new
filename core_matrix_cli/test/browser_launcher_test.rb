require "test_helper"

class CoreMatrixCLIBrowserLauncherTest < CoreMatrixCLITestCase
  def test_open_returns_false_without_invoking_shell_when_browser_is_disabled
    launcher = CoreMatrixCLI::BrowserLauncher.new(
      shell_runner: ->(*) { raise "should not launch browser" }
    )

    with_env("CORE_MATRIX_CLI_DISABLE_BROWSER" => "1") do
      assert_equal false, launcher.open("https://example.test/device")
    end
  end
end
