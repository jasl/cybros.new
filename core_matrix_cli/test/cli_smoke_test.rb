require "test_helper"

class CoreMatrixCLISmokeTest < Minitest::Test
  def test_cli_exposes_root_commands
    assert_includes CoreMatrixCLI::CLI.all_commands.keys, "init"
    assert_includes CoreMatrixCLI::CLI.all_commands.keys, "auth"
    assert_includes CoreMatrixCLI::CLI.all_commands.keys, "status"
    assert_includes CoreMatrixCLI::CLI.all_commands.keys, "providers"
    assert_includes CoreMatrixCLI::CLI.all_commands.keys, "workspace"
    assert_includes CoreMatrixCLI::CLI.all_commands.keys, "agent"
    assert_includes CoreMatrixCLI::CLI.all_commands.keys, "ingress"
  end
end
