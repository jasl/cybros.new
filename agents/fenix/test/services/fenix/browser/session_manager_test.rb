require "test_helper"
require "fileutils"
require "stringio"
require "tmpdir"

class Fenix::Browser::SessionManagerTest < ActiveSupport::TestCase
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
    Fenix::Browser::SessionManager.reset!
  end

  teardown do
    Fenix::Browser::SessionManager.reset!
  end

  test "open registers a session and close removes it" do
    hosts = []
    host_factory = lambda do |session_id:|
      host = FakeHost.new(commands: [], closed: false)
      hosts << { session_id:, host: }
      host
    end

    opened = Fenix::Browser::SessionManager.call(
      action: "open",
      url: "https://example.com",
      host_factory: host_factory
    )

    browser_session_id = opened.fetch("browser_session_id")

    assert_equal "https://example.com", opened.fetch("current_url")
    assert Fenix::Browser::SessionManager.lookup(browser_session_id: browser_session_id)

    closed = Fenix::Browser::SessionManager.call(
      action: "close",
      browser_session_id: browser_session_id
    )

    assert_equal true, closed.fetch("closed")
    assert_nil Fenix::Browser::SessionManager.lookup(browser_session_id: browser_session_id)
    assert_equal true, hosts.first.fetch(:host).closed
  end

  test "navigate get_content and screenshot dispatch through the stored host" do
    host = FakeHost.new(commands: [], closed: false)
    host_factory = ->(session_id:) { host }

    opened = Fenix::Browser::SessionManager.call(
      action: "open",
      url: "https://example.com",
      host_factory: host_factory
    )

    browser_session_id = opened.fetch("browser_session_id")

    navigated = Fenix::Browser::SessionManager.call(
      action: "navigate",
      browser_session_id: browser_session_id,
      url: "https://example.com/docs"
    )
    content = Fenix::Browser::SessionManager.call(
      action: "get_content",
      browser_session_id: browser_session_id
    )
    screenshot = Fenix::Browser::SessionManager.call(
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

    opened = Fenix::Browser::SessionManager.call(
      action: "open",
      url: "https://example.com",
      host_factory: host_factory
    )
    browser_session_id = opened.fetch("browser_session_id")

    Fenix::Browser::SessionManager.call(
      action: "navigate",
      browser_session_id: browser_session_id,
      url: "https://example.com/docs"
    )

    listed = Fenix::Browser::SessionManager.call(action: "list")
    info = Fenix::Browser::SessionManager.call(action: "info", browser_session_id: browser_session_id)

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

    owned = Fenix::Browser::SessionManager.call(
      action: "open",
      url: "https://example.com",
      host_factory: host_factory,
      runtime_owner_id: "task-1"
    )
    Fenix::Browser::SessionManager.call(
      action: "open",
      url: "https://example.org",
      host_factory: host_factory,
      runtime_owner_id: "task-2"
    )

    listed = Fenix::Browser::SessionManager.call(action: "list", runtime_owner_id: "task-1")
    info = Fenix::Browser::SessionManager.call(
      action: "info",
      browser_session_id: owned.fetch("browser_session_id"),
      runtime_owner_id: "task-1"
    )

    assert_equal [owned.fetch("browser_session_id")], listed.fetch("entries").map { |entry| entry.fetch("browser_session_id") }
    assert_equal owned.fetch("browser_session_id"), info.fetch("browser_session_id")

    assert_raises(Fenix::Browser::SessionManager::ValidationError) do
      Fenix::Browser::SessionManager.call(
        action: "info",
        browser_session_id: owned.fetch("browser_session_id"),
        runtime_owner_id: "task-2"
      )
    end
  end

  test "playwright host wraps broken pipes as host errors" do
    host = Fenix::Browser::SessionManager::PlaywrightHost.allocate
    wait_thread = Thread.new { sleep 5 }
    broken_stdin = Object.new

    broken_stdin.define_singleton_method(:puts) { |_payload| raise Errno::EPIPE, "broken pipe" }
    broken_stdin.define_singleton_method(:flush) { true }

    host.instance_variable_set(:@stdin, broken_stdin)
    host.instance_variable_set(:@stdout, StringIO.new)
    host.instance_variable_set(:@stderr, StringIO.new("node exited"))
    host.instance_variable_set(:@wait_thread, wait_thread)
    host.define_singleton_method(:ensure_started!) { true }

    error = assert_raises(Fenix::Browser::SessionManager::HostError) do
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

      host = Fenix::Browser::SessionManager::PlaywrightHost.new(
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

  private

  def write_executable(path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "#!/usr/bin/env bash\nexit 0\n")
    FileUtils.chmod("+x", path)
  end
end
