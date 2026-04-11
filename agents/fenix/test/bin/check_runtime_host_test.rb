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
      stub_command(fake_bin, "bundle", "Bundler version 4.0.10")

      stdout, stderr, status = Open3.capture3(
        {
          "FENIX_HOST_CHECK_PATH" => "#{fake_bin}:#{ENV.fetch("PATH")}",
        },
        "bash",
        check_runtime_host.to_s
      )

      assert status.success?, "expected success, got exit #{status.exitstatus}: #{stderr.presence || stdout}"
      assert_equal "", stderr
      assert_match(/host contract satisfied/i, stdout)
    end
  end

  test "does not require runtime-host browser or python toolchains" do
    Dir.mktmpdir("fenix-host-check-lightweight") do |tmpdir|
      fake_bin = File.join(tmpdir, "bin")
      FileUtils.mkdir_p(fake_bin)

      stub_command(fake_bin, "ruby", "ruby 4.0.2p0 (2026-03-15 revision abc123) [arm64-darwin]")
      stub_command(fake_bin, "bundle", "Bundler version 4.0.10")

      stdout, stderr, status = Open3.capture3(
        {
          "FENIX_HOST_CHECK_PATH" => "#{fake_bin}:#{ENV.fetch("PATH")}",
        },
        "bash",
        check_runtime_host.to_s
      )

      assert status.success?, "expected success without browser/python runtime dependencies: #{stderr.presence || stdout}"
    end
  end

  test "does not require git or other execution-runtime-only developer tools" do
    Dir.mktmpdir("fenix-host-check-minimal") do |tmpdir|
      fake_bin = File.join(tmpdir, "bin")
      FileUtils.mkdir_p(fake_bin)

      stub_command(fake_bin, "ruby", "ruby 4.0.2p0 (2026-03-15 revision abc123) [arm64-darwin]")
      stub_command(fake_bin, "bundle", "Bundler version 4.0.10")

      stdout, stderr, status = Open3.capture3(
        {
          "FENIX_HOST_CHECK_PATH" => "#{fake_bin}:#{ENV.fetch("PATH")}",
        },
        "bash",
        check_runtime_host.to_s
      )

      assert status.success?, "expected minimal Rails host contract: #{stderr.presence || stdout}"
      assert_equal "", stderr
      assert_match(/host contract satisfied/i, stdout)
    end
  end

  test "lists only the lightweight prerequisites when missing" do
    Dir.mktmpdir("fenix-host-check-missing") do |tmpdir|
      fake_bin = File.join(tmpdir, "bin")
      FileUtils.mkdir_p(fake_bin)

      _stdout, stderr, status = Open3.capture3(
        {
          "FENIX_HOST_CHECK_PATH" => "#{fake_bin}:#{ENV.fetch("PATH")}",
        },
        "bash",
        check_runtime_host.to_s
      )

      assert_match(/missing prerequisites/i, stderr)
      assert_match(/bundler/, stderr)
      refute_match(/playwright/i, stderr)
      refute_match(/python/i, stderr)
    end
  end

  private

  def check_runtime_host
    Rails.root.join("bin", "check-runtime-host")
  end

  def stub_command(bin_dir, name, output)
    path = File.join(bin_dir, name)
    File.write(path, <<~SH)
      #!/bin/sh
      echo #{output.inspect}
    SH
    FileUtils.chmod("+x", path)
  end
end
