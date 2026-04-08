require "test_helper"
require "fileutils"
require "open3"
require "tmpdir"

class CheckRuntimeHostTest < ActiveSupport::TestCase
  test "passes when the documented bare-metal host contract is satisfied" do
    Dir.mktmpdir("fenix-host-check") do |tmpdir|
      fake_bin = File.join(tmpdir, "bin")
      FileUtils.mkdir_p(fake_bin)

      stub_command(fake_bin, "ruby", "ruby 4.0.2p0 (2026-03-15 revision abc123) [arm64-darwin]")
      stub_command(fake_bin, "bundle", "Bundler version 4.0.8")
      stub_command(fake_bin, "node", "v22.22.2")
      stub_command(fake_bin, "npm", "11.12.1")
      stub_command(fake_bin, "corepack", "0.34.1")
      stub_command(fake_bin, "pnpm", "10.33.0")
      stub_command(fake_bin, "python3", "Python 3.12.8")
      stub_command(fake_bin, "uv", "uv 0.11.4 (aarch64-apple-darwin)")
      stub_command(fake_bin, "git", "git version 2.51.0")
      stub_command(fake_bin, "curl", "curl 8.17.0")
      stub_command(fake_bin, "jq", "jq-1.8.1")
      stub_command(fake_bin, "rg", "ripgrep 14.1.1")
      stub_command(fake_bin, "fd", "fd 10.3.0")
      stub_command(fake_bin, "sqlite3", "3.50.4 2025-07-30")

      browser_path = File.join(tmpdir, "chrome")
      File.write(browser_path, "#!/usr/bin/env bash\necho 'Chromium 145.0.7632.6'\n")
      FileUtils.chmod("+x", browser_path)

      stdout, stderr, status = Open3.capture3(
        {
          "FENIX_HOST_CHECK_PATH" => fake_bin,
          "PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH" => browser_path,
        },
        "bash",
        check_runtime_host.to_s
      )

      assert status.success?, "expected success, got exit #{status.exitstatus}: #{stderr.presence || stdout}"
      assert_equal "", stderr
      assert_match(/host contract satisfied/i, stdout)
    end
  end

  test "lists missing prerequisites clearly" do
    Dir.mktmpdir("fenix-host-check-missing") do |tmpdir|
      fake_bin = File.join(tmpdir, "bin")
      FileUtils.mkdir_p(fake_bin)

      stdout, stderr, status = Open3.capture3(
        {
          "FENIX_HOST_CHECK_PATH" => fake_bin,
        },
        "bash",
        check_runtime_host.to_s
      )

      assert_not status.success?, "expected failure, got success: #{stdout}"
      assert_match(/missing prerequisites/i, stderr)
      assert_match(/ruby/, stderr)
      assert_match(/node/, stderr)
      assert_match(/PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH/, stderr)
    end
  end

  private

  def check_runtime_host
    Rails.root.join("bin", "check-runtime-host")
  end

  def stub_command(bin_dir, name, output)
    path = File.join(bin_dir, name)
    File.write(path, <<~SH)
      #!/usr/bin/env bash
      echo #{output.inspect}
    SH
    FileUtils.chmod("+x", path)
  end
end
