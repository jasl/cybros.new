require "test_helper"
require "open3"

class ExecutableContractTest < Minitest::Test
  def test_exe_nexus_exists_and_is_executable
    path = File.expand_path("../exe/nexus", __dir__)

    assert File.exist?(path), "expected #{path} to exist"
    assert File.executable?(path), "expected #{path} to be executable"
  end

  def test_exe_nexus_prints_help
    stdout, stderr, status = capture_cli("--help")

    assert status.success?, "stderr=#{stderr}"
    assert_includes stdout, "nexus"
    assert_includes stdout, "run"
  end

  def test_exe_nexus_run_prints_help
    stdout, stderr, status = capture_cli("run", "--help")

    assert status.success?, "stderr=#{stderr}"
    assert_includes stdout, "Usage:"
    assert_includes stdout, "run"
  end

  private

  def capture_cli(*args)
    Open3.capture3(
      {
        "BUNDLE_BIN_PATH" => nil,
        "BUNDLE_GEMFILE" => nil,
        "RUBYLIB" => nil,
        "RUBYOPT" => nil,
      },
      Gem.ruby, "./exe/nexus", *args,
      chdir: File.expand_path("..", __dir__)
    )
  end
end
