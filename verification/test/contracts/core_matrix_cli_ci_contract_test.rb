require_relative "../test_helper"

class CoreMatrixCliCiContractTest < Minitest::Test
  def test_root_ci_uses_maintainable_cli_commands
    workflow = Verification.repo_root.join(".github", "workflows", "ci.yml").read

    assert_includes workflow, "bundle exec rake test"
    assert_includes workflow, "bundle exec rubocop --no-server"
    refute_includes workflow, "test/config_store_test.rb"
    refute_includes workflow, "test/http_client_test.rb"
    refute_includes workflow, "test/init_command_test.rb"
  end
end
