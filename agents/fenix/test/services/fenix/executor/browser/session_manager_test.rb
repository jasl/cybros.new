require "test_helper"
require "fileutils"
require "json"
require "open3"
require "stringio"
require "tmpdir"

class Fenix::Executor::Browser::SessionManagerTest < ActiveSupport::TestCase
  FakeHost = Struct.new(:commands, :closed, keyword_init: true) do
    def dispatch(command:, arguments:)
      commands << { "command" => command, "arguments" => arguments }

      case command
      when "open"
        { "current_url" => arguments["url"] }
      when "navigate"
        { "current_url" => arguments["url"] }
      when "get_content"
        { "current_url" => "https://example.com", "content" => "Example page" }
      when "screenshot"
        { "current_url" => "https://example.com", "mime_type" => "image/png", "image_base64" => "cG5n" }
      when "close"
        self.closed = true
        { "closed" => true }
      else
        raise "unexpected command #{command}"
      end
    end

    def close
      self.closed = true
    end
  end

  setup do
    Fenix::Executor::Browser::SessionManager.reset!
  end

  teardown do
    Fenix::Executor::Browser::SessionManager.reset!
  end

  test "open registers a session and close removes it" do
    hosts = []
    host_factory = lambda do |session_id:|
      host = FakeHost.new(commands: [], closed: false)
      hosts << { session_id:, host: }
      host
    end

    opened = Fenix::Executor::Browser::SessionManager.call(
      action: "open",
      url: "https://example.com",
      host_factory: host_factory
    )

    browser_session_id = opened.fetch("browser_session_id")

    assert_equal "https://example.com", opened.fetch("current_url")
    assert Fenix::Executor::Browser::SessionManager.lookup(browser_session_id: browser_session_id)

    closed = Fenix::Executor::Browser::SessionManager.call(
      action: "close",
      browser_session_id: browser_session_id
    )

    assert_equal true, closed.fetch("closed")
    assert_nil Fenix::Executor::Browser::SessionManager.lookup(browser_session_id: browser_session_id)
    assert_equal true, hosts.first.fetch(:host).closed
  end

  test "navigate get_content and screenshot dispatch through the stored host" do
    host = FakeHost.new(commands: [], closed: false)
    host_factory = ->(session_id:) { host }

    opened = Fenix::Executor::Browser::SessionManager.call(
      action: "open",
      url: "https://example.com",
      host_factory: host_factory
    )

    browser_session_id = opened.fetch("browser_session_id")

    navigated = Fenix::Executor::Browser::SessionManager.call(
      action: "navigate",
      browser_session_id: browser_session_id,
      url: "https://example.com/docs"
    )
    content = Fenix::Executor::Browser::SessionManager.call(
      action: "get_content",
      browser_session_id: browser_session_id
    )
    screenshot = Fenix::Executor::Browser::SessionManager.call(
      action: "screenshot",
      browser_session_id: browser_session_id
    )

    assert_equal "https://example.com/docs", navigated.fetch("current_url")
    assert_equal "Example page", content.fetch("content")
    assert_equal "image/png", screenshot.fetch("mime_type")
    assert_equal %w[open navigate get_content screenshot], host.commands.map { |entry| entry.fetch("command") }
  end

  test "list and info expose registered session metadata" do
    host = FakeHost.new(commands: [], closed: false)
    host_factory = ->(session_id:) { host }

    opened = Fenix::Executor::Browser::SessionManager.call(
      action: "open",
      url: "https://example.com",
      host_factory: host_factory
    )
    browser_session_id = opened.fetch("browser_session_id")

    Fenix::Executor::Browser::SessionManager.call(
      action: "navigate",
      browser_session_id: browser_session_id,
      url: "https://example.com/docs"
    )

    listed = Fenix::Executor::Browser::SessionManager.call(action: "list")
    info = Fenix::Executor::Browser::SessionManager.call(action: "info", browser_session_id: browser_session_id)

    assert_equal browser_session_id, listed.fetch("entries").fetch(0).fetch("browser_session_id")
    assert_equal "https://example.com/docs", listed.fetch("entries").fetch(0).fetch("current_url")
    assert_equal browser_session_id, info.fetch("browser_session_id")
    assert_equal "https://example.com/docs", info.fetch("current_url")
  end

  test "list and info can be scoped to the owning execution" do
    hosts = [
      FakeHost.new(commands: [], closed: false),
      FakeHost.new(commands: [], closed: false),
    ]
    host_factory = ->(session_id:) { hosts.shift || FakeHost.new(commands: [], closed: false) }

    owned = Fenix::Executor::Browser::SessionManager.call(
      action: "open",
      url: "https://example.com",
      host_factory: host_factory,
      runtime_owner_id: "task-1"
    )
    Fenix::Executor::Browser::SessionManager.call(
      action: "open",
      url: "https://example.org",
      host_factory: host_factory,
      runtime_owner_id: "task-2"
    )

    listed = Fenix::Executor::Browser::SessionManager.call(action: "list", runtime_owner_id: "task-1")
    info = Fenix::Executor::Browser::SessionManager.call(
      action: "info",
      browser_session_id: owned.fetch("browser_session_id"),
      runtime_owner_id: "task-1"
    )

    assert_equal [owned.fetch("browser_session_id")], listed.fetch("entries").map { |entry| entry.fetch("browser_session_id") }
    assert_equal owned.fetch("browser_session_id"), info.fetch("browser_session_id")

    assert_raises(Fenix::Executor::Browser::SessionManager::ValidationError) do
      Fenix::Executor::Browser::SessionManager.call(
        action: "info",
        browser_session_id: owned.fetch("browser_session_id"),
        runtime_owner_id: "task-2"
      )
    end
  end

  test "playwright host wraps broken pipes as host errors" do
    host = Fenix::Executor::Browser::SessionManager::PlaywrightHost.allocate
    wait_thread = Thread.new { sleep 5 }
    broken_stdin = Object.new

    broken_stdin.define_singleton_method(:puts) { |_payload| raise Errno::EPIPE, "broken pipe" }
    broken_stdin.define_singleton_method(:flush) { true }

    host.instance_variable_set(:@stdin, broken_stdin)
    host.instance_variable_set(:@stdout, StringIO.new)
    host.instance_variable_set(:@stderr, StringIO.new("node exited"))
    host.instance_variable_set(:@wait_thread, wait_thread)
    host.define_singleton_method(:ensure_started!) { true }

    error = assert_raises(Fenix::Executor::Browser::SessionManager::HostError) do
      host.dispatch(command: "open", arguments: {})
    end

    assert_match(/browser host communication failed/i, error.message)
  ensure
    wait_thread&.kill
    wait_thread&.join
  end

  test "playwright host falls back to a discovered managed browser root when the configured path is empty" do
    Dir.mktmpdir("fenix-playwright-root") do |tmpdir|
      configured_root = File.join(tmpdir, "configured")
      fallback_root = File.join(tmpdir, "fallback")
      write_executable(File.join(fallback_root, "chromium-1208", "chrome-linux", "headless_shell"))

      host = Fenix::Executor::Browser::SessionManager::PlaywrightHost.new(
        session_id: "browser-session-test",
        runtime_env: { "PLAYWRIGHT_BROWSERS_PATH" => configured_root },
        playwright_browser_roots: [fallback_root]
      )

      assert_equal(
        { "PLAYWRIGHT_BROWSERS_PATH" => fallback_root },
        host.send(:browser_environment)
      )
    end
  end

  test "browser host can resolve a globally installed playwright package" do
    Dir.mktmpdir("fenix-global-playwright") do |tmpdir|
      script_path = write_session_host_copy(tmpdir)
      fake_bin = File.join(tmpdir, "bin")
      global_root = File.join(tmpdir, "node_modules")
      playwright_root = File.join(global_root, "playwright")
      FileUtils.mkdir_p(fake_bin)
      FileUtils.mkdir_p(playwright_root)

      File.write(
        File.join(playwright_root, "package.json"),
        JSON.pretty_generate(
          name: "playwright",
          version: "1.59.1",
          exports: {
            "." => {
              import: "./index.mjs",
            },
          }
        )
      )
      File.write(
        File.join(playwright_root, "index.mjs"),
        <<~JAVASCRIPT
          export const chromium = {
            async launch() {
              let currentUrl = "about:blank";

              return {
                async newPage() {
                  return {
                    async goto(url) {
                      currentUrl = url;
                    },
                    url() {
                      return currentUrl;
                    },
                  };
                },
                async close() {},
              };
            },
          };
        JAVASCRIPT
      )
      File.write(
        File.join(fake_bin, "npm"),
        <<~SH
          #!/usr/bin/env bash
          if [[ "$1" == "root" && "$2" == "-g" ]]; then
            echo #{global_root.inspect}
            exit 0
          fi

          exit 1
        SH
      )
      FileUtils.chmod("+x", File.join(fake_bin, "npm"))

      stdout, stderr, status = Open3.capture3(
        {
          "PATH" => "#{fake_bin}:#{ENV.fetch("PATH")}",
        },
        "node",
        script_path,
        stdin_data: <<~JSONL
          {"command":"open","arguments":{"url":"https://example.com"}}
        JSONL
      )

      assert status.success?, "expected global playwright fallback to work: #{stderr.presence || stdout}"
      responses = stdout.lines.map { |line| JSON.parse(line) }
      assert_equal "https://example.com", responses.first.fetch("payload").fetch("current_url")
      assert_equal 1, responses.length
    end
  end

  test "browser host does not hide broken local playwright packages behind the global fallback" do
    Dir.mktmpdir("fenix-global-playwright-broken-local") do |tmpdir|
      script_path = write_session_host_copy(tmpdir)
      fake_bin = File.join(tmpdir, "bin")
      global_root = File.join(tmpdir, "global_node_modules")
      playwright_root = File.join(global_root, "playwright")
      local_playwright_root = File.join(tmpdir, "node_modules", "playwright")
      FileUtils.mkdir_p(fake_bin)
      FileUtils.mkdir_p(playwright_root)
      FileUtils.mkdir_p(local_playwright_root)

      File.write(
        File.join(playwright_root, "package.json"),
        JSON.pretty_generate(
          name: "playwright",
          version: "1.59.1",
          exports: {
            "." => {
              import: "./index.mjs",
            },
          }
        )
      )
      File.write(
        File.join(playwright_root, "index.mjs"),
        <<~JAVASCRIPT
          export const chromium = {
            async launch() {
              throw new Error("global fallback should not run");
            },
          };
        JAVASCRIPT
      )
      File.write(
        File.join(local_playwright_root, "package.json"),
        JSON.pretty_generate(
          name: "playwright",
          version: "1.59.1",
          exports: {
            "." => {
              import: "./index.mjs",
            },
          }
        )
      )
      File.write(
        File.join(local_playwright_root, "index.mjs"),
        <<~JAVASCRIPT
          throw new Error("local playwright is broken");
        JAVASCRIPT
      )
      File.write(
        File.join(fake_bin, "npm"),
        <<~SH
          #!/usr/bin/env bash
          if [[ "$1" == "root" && "$2" == "-g" ]]; then
            echo #{global_root.inspect}
            exit 0
          fi

          exit 1
        SH
      )
      FileUtils.chmod("+x", File.join(fake_bin, "npm"))

      stdout, stderr, status = Open3.capture3(
        {
          "PATH" => "#{fake_bin}:#{ENV.fetch("PATH")}",
        },
        "node",
        script_path,
        stdin_data: <<~JSONL
          {"command":"open","arguments":{"url":"https://example.com"}}
        JSONL
      )

      assert status.success?, "browser host should report JSON errors instead of crashing: #{stderr.presence || stdout}"
      response = JSON.parse(stdout.lines.first)
      assert_match(/local playwright is broken/, response.fetch("error"))
    end
  end

  private

  def write_executable(path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "#!/usr/bin/env bash\nexit 0\n")
    FileUtils.chmod("+x", path)
  end

  def write_session_host_copy(tmpdir)
    path = File.join(tmpdir, "session_host.mjs")
    FileUtils.cp(Rails.root.join("scripts", "browser", "session_host.mjs"), path)
    path
  end
end
