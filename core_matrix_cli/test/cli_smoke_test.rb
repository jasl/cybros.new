require "test_helper"

class CoreMatrixCLISmokeTest < CoreMatrixCLITestCase
  def test_cli_exposes_root_commands
    assert_includes CoreMatrixCLI::CLI.all_commands.keys, "init"
    assert_includes CoreMatrixCLI::CLI.all_commands.keys, "auth"
    assert_includes CoreMatrixCLI::CLI.all_commands.keys, "status"
    assert_includes CoreMatrixCLI::CLI.all_commands.keys, "providers"
    assert_includes CoreMatrixCLI::CLI.all_commands.keys, "workspace"
    assert_includes CoreMatrixCLI::CLI.all_commands.keys, "agent"
    assert_includes CoreMatrixCLI::CLI.all_commands.keys, "ingress"
  end

  def test_root_help_hides_tree_command
    runtime = FakeRuntime.new(
      config_store: CoreMatrixCLI::ConfigStore.new(path: tmp_path("config.json")),
      credential_store: CoreMatrixCLI::CredentialStores::FileStore.new(path: tmp_path("credentials.json"))
    )

    output = run_cli("help", runtime: runtime)

    refute_includes output, "cmctl tree"
  end
end
