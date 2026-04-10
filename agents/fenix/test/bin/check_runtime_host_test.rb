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
      stub_command(fake_bin, "node", "v24.14.1")
      stub_command(fake_bin, "npm", "11.12.1")
      stub_command(fake_bin, "corepack", "0.34.1")
      stub_command(fake_bin, "pnpm", "10.33.0")
      stub_command(fake_bin, "playwright", "Version 1.59.1")
      stub_uv(fake_bin)
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
          "FENIX_HOST_CHECK_PATH" => "#{fake_bin}:#{ENV.fetch("PATH")}",
          "PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH" => browser_path,
          "FENIX_HOST_CHECK_RUNTIME_ROOT" => File.join(tmpdir, "fenix-home"),
        },
        "bash",
        check_runtime_host.to_s
      )

      assert status.success?, "expected success, got exit #{status.exitstatus}: #{stderr.presence || stdout}"
      assert_equal "", stderr
      assert_match(/host contract satisfied/i, stdout)
    end
  end

  test "requires a globally installed playwright package" do
    Dir.mktmpdir("fenix-host-check-playwright") do |tmpdir|
      fake_bin = File.join(tmpdir, "bin")
      FileUtils.mkdir_p(fake_bin)

      stub_command(fake_bin, "ruby", "ruby 4.0.2p0 (2026-03-15 revision abc123) [arm64-darwin]")
      stub_command(fake_bin, "bundle", "Bundler version 4.0.10")
      stub_command(fake_bin, "node", "v24.14.1")
      stub_command(fake_bin, "npm", "11.12.1")
      stub_command(fake_bin, "corepack", "0.34.1")
      stub_command(fake_bin, "pnpm", "10.33.0")
      stub_uv(fake_bin)
      stub_command(fake_bin, "git", "git version 2.51.0")
      stub_command(fake_bin, "curl", "curl 8.17.0")
      stub_command(fake_bin, "jq", "jq-1.8.1")
      stub_command(fake_bin, "rg", "ripgrep 14.1.1")
      stub_command(fake_bin, "fd", "fd 10.3.0")
      stub_command(fake_bin, "sqlite3", "3.50.4 2025-07-30")

      browser_path = File.join(tmpdir, "chrome")
      File.write(browser_path, "#!/usr/bin/env bash\necho 'Chromium 145.0.7632.6'\n")
      FileUtils.chmod("+x", browser_path)

      _stdout, stderr, status = Open3.capture3(
        {
          "FENIX_HOST_CHECK_PATH" => "#{fake_bin}:#{ENV.fetch("PATH")}",
          "PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH" => browser_path,
          "FENIX_HOST_CHECK_RUNTIME_ROOT" => File.join(tmpdir, "fenix-home"),
        },
        "bash",
        check_runtime_host.to_s
      )

      assert_not status.success?, "expected failure without playwright on the host"
      assert_match(/playwright 1\.59\.1 is required/i, stderr)
    end
  end

  test "does not require a system python3 binary when uv can provision the managed runtime" do
    Dir.mktmpdir("fenix-host-check-managed-python") do |tmpdir|
      fake_bin = File.join(tmpdir, "bin")
      FileUtils.mkdir_p(fake_bin)

      stub_command(fake_bin, "ruby", "ruby 4.0.2p0 (2026-03-15 revision abc123) [arm64-darwin]")
      stub_command(fake_bin, "bundle", "Bundler version 4.0.10")
      stub_command(fake_bin, "node", "v24.14.1")
      stub_command(fake_bin, "npm", "11.12.1")
      stub_command(fake_bin, "corepack", "0.34.1")
      stub_command(fake_bin, "pnpm", "10.33.0")
      stub_command(fake_bin, "playwright", "Version 1.59.1")
      stub_uv(fake_bin)
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
          "FENIX_HOST_CHECK_PATH" => "#{fake_bin}:#{ENV.fetch("PATH")}",
          "PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH" => browser_path,
          "FENIX_HOST_CHECK_RUNTIME_ROOT" => File.join(tmpdir, "fenix-home"),
        },
        "bash",
        check_runtime_host.to_s
      )

      assert status.success?, "expected uv-managed python to satisfy the host contract: #{stderr.presence || stdout}"
      assert_equal "", stderr
      assert_match(/host contract satisfied/i, stdout)
    end
  end

  test "requires uv-managed pip in the provisioned runtime" do
    Dir.mktmpdir("fenix-host-check-managed-pip") do |tmpdir|
      fake_bin = File.join(tmpdir, "bin")
      FileUtils.mkdir_p(fake_bin)

      stub_command(fake_bin, "ruby", "ruby 4.0.2p0 (2026-03-15 revision abc123) [arm64-darwin]")
      stub_command(fake_bin, "bundle", "Bundler version 4.0.10")
      stub_command(fake_bin, "node", "v24.14.1")
      stub_command(fake_bin, "npm", "11.12.1")
      stub_command(fake_bin, "corepack", "0.34.1")
      stub_command(fake_bin, "pnpm", "10.33.0")
      stub_command(fake_bin, "playwright", "Version 1.59.1")
      stub_uv(fake_bin, with_pip: false)
      stub_command(fake_bin, "git", "git version 2.51.0")
      stub_command(fake_bin, "curl", "curl 8.17.0")
      stub_command(fake_bin, "jq", "jq-1.8.1")
      stub_command(fake_bin, "rg", "ripgrep 14.1.1")
      stub_command(fake_bin, "fd", "fd 10.3.0")
      stub_command(fake_bin, "sqlite3", "3.50.4 2025-07-30")

      browser_path = File.join(tmpdir, "chrome")
      File.write(browser_path, "#!/usr/bin/env bash\necho 'Chromium 145.0.7632.6'\n")
      FileUtils.chmod("+x", browser_path)

      _stdout, stderr, status = Open3.capture3(
        {
          "FENIX_HOST_CHECK_PATH" => "#{fake_bin}:#{ENV.fetch("PATH")}",
          "PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH" => browser_path,
          "FENIX_HOST_CHECK_RUNTIME_ROOT" => File.join(tmpdir, "fenix-home"),
        },
        "bash",
        check_runtime_host.to_s
      )

      assert_not status.success?, "expected failure without uv-managed pip"
      assert_match(/managed pip command is missing/i, stderr)
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
      #!/bin/sh
      echo #{output.inspect}
    SH
    FileUtils.chmod("+x", path)
  end

  def stub_uv(bin_dir, with_pip: true)
    path = File.join(bin_dir, "uv")
    File.write(path, <<~SH)
      #!/bin/sh
      set -eu

      if [ "${1:-}" = "--version" ]; then
        echo "uv 0.11.5 (stub)"
        exit 0
      fi

      if [ "${1:-}" = "venv" ]; then
        target=""
        for arg in "$@"; do
          target="$arg"
        done

        mkdir -p "${target}/bin"
        cat > "${target}/bin/python" <<'PY'
#!/bin/sh
echo "Python 3.12.0"
PY
        cp "${target}/bin/python" "${target}/bin/python3"
        #{with_pip ? <<~'PIP'.strip : ":"}
        cat > "${target}/bin/pip" <<'SCRIPT'
#!/bin/sh
echo "pip 25.0 from ${0%/*}/../lib/python3.12/site-packages/pip (python 3.12)"
SCRIPT
        cp "${target}/bin/pip" "${target}/bin/pip3"
        PIP
        chmod +x "${target}/bin/python" "${target}/bin/python3"#{with_pip ? ' "${target}/bin/pip" "${target}/bin/pip3"' : ""}
        exit 0
      fi

      exit 1
    SH
    FileUtils.chmod("+x", path)
  end
end
