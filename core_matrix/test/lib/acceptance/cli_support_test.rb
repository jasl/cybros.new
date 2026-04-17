require "test_helper"
require Rails.root.join("../acceptance/lib/cli_support")
require "tmpdir"

class Acceptance::CliSupportTest < ActiveSupport::TestCase
  FakeStatus = Struct.new(:success?)

  test "run! executes cmctl with isolated automation env and captures evidence" do
    Dir.mktmpdir do |dir|
      artifact_dir = Pathname.new(dir)
      captured_env = nil
      captured_command = nil
      captured_input = nil
      captured_chdir = nil

      runner = lambda do |env, *command, stdin_data:, chdir:|
        captured_env = env
        captured_command = command
        captured_input = stdin_data
        captured_chdir = chdir

        FileUtils.mkdir_p(File.dirname(env.fetch("CORE_MATRIX_CLI_CONFIG_PATH")))
        File.write(env.fetch("CORE_MATRIX_CLI_CONFIG_PATH"), JSON.pretty_generate({ "workspace_id" => "ws_123" }))
        File.write(env.fetch("CORE_MATRIX_CLI_CREDENTIAL_PATH"), JSON.generate({ "session_token" => "sess_123" }))

        ["ok\n", "", FakeStatus.new(true)]
      end

      original_bundle_bin_path = ENV["BUNDLE_BIN_PATH"]
      original_rubyopt = ENV["RUBYOPT"]
      original_bundle_gemfile = ENV["BUNDLE_GEMFILE"]

      ENV["BUNDLE_BIN_PATH"] = "/tmp/core-matrix-bundle-bin"
      ENV["RUBYOPT"] = "-rbundler/setup"
      ENV["BUNDLE_GEMFILE"] = Acceptance::CliSupport.send(:repo_root).join("core_matrix", "Gemfile").to_s

      result = Acceptance::CliSupport.run!(
        artifact_dir: artifact_dir,
        label: "init",
        args: ["init"],
        input: "https://core.example.com\n",
        runner: runner
      )

      assert_equal ["bundle", "exec", "./exe/cmctl", "init"], captured_command
      assert_equal "https://core.example.com\n", captured_input
      assert_equal Acceptance::CliSupport.send(:repo_root).join("core_matrix_cli").to_s, captured_chdir
      assert_equal "1", captured_env.fetch("BUNDLE_FROZEN")
      assert_equal Acceptance::CliSupport.send(:repo_root).join("core_matrix_cli", "Gemfile").to_s, captured_env.fetch("BUNDLE_GEMFILE")
      refute_includes captured_env.keys, "BUNDLE_BIN_PATH"
      refute_match(/bundler\/setup/, captured_env.fetch("RUBYOPT", ""))
      assert_equal "file", captured_env.fetch("CORE_MATRIX_CLI_CREDENTIAL_STORE")
      assert_equal "1", captured_env.fetch("CORE_MATRIX_CLI_DISABLE_BROWSER")
      assert_equal({ "workspace_id" => "ws_123" }, result.fetch("config"))
      assert_equal({ "session_token" => "sess_123" }, result.fetch("credentials"))
      assert_equal "ok\n", artifact_dir.join("evidence", "cli", "init.stdout.txt").read
      assert_equal "", artifact_dir.join("evidence", "cli", "init.stderr.txt").read
    ensure
      ENV["BUNDLE_BIN_PATH"] = original_bundle_bin_path
      ENV["RUBYOPT"] = original_rubyopt
      ENV["BUNDLE_GEMFILE"] = original_bundle_gemfile
    end
  end
end
