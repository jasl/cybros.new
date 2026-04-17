$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "test_helper"
require "open3"

class ExecutableContractTest < Minitest::Test
  def test_exe_cmctl_exists_and_is_executable
    path = File.expand_path("../exe/cmctl", __dir__)

    assert File.exist?(path), "expected #{path} to exist"
    assert File.executable?(path), "expected #{path} to be executable"
  end

  def test_exe_cmctl_boots_the_cli
    stdout, stderr, status = Open3.capture3(
      { "BUNDLE_GEMFILE" => File.expand_path("../Gemfile", __dir__) },
      "bundle", "exec", "./exe/cmctl", "--help",
      chdir: File.expand_path("..", __dir__)
    )

    assert status.success?, "expected help command to pass, stderr=#{stderr}"
    assert_includes stdout, "cmctl"
  end
end
