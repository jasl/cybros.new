require "tmpdir"
require_relative "../test_helper"
require "verification/support/cli_support"

class CliSupportTest < Minitest::Test
  def test_run_uses_bundle_exec_and_exe_cmctl_from_core_matrix_cli
    calls = []
    status = Struct.new(:success?).new(true)
    artifact_dir = Dir.mktmpdir("cli_support_test")
    runner = lambda do |env, *command, **kwargs|
      calls << { env:, command:, kwargs: }
      ["", "", status]
    end

    Verification::CliSupport.run!(
      artifact_dir: artifact_dir,
      label: "status",
      args: ["status"],
      runner: runner
    )

    assert_equal ["bundle", "exec", "./exe/cmctl", "status"], calls.fetch(0).fetch(:command)
    assert_equal "/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli", calls.fetch(0).dig(:kwargs, :chdir)
    assert_equal "/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/Gemfile", calls.fetch(0).dig(:env, "BUNDLE_GEMFILE")
  ensure
    FileUtils.rm_rf(artifact_dir) if artifact_dir
  end
end
