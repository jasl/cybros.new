require "test_helper"

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
      host_factory:
    )

    browser_session_id = opened.fetch("browser_session_id")

    assert_equal "https://example.com", opened.fetch("current_url")
    assert Fenix::Browser::SessionManager.lookup(browser_session_id:)

    closed = Fenix::Browser::SessionManager.call(
      action: "close",
      browser_session_id:,
      host_factory:
    )

    assert_equal true, closed.fetch("closed")
    assert_nil Fenix::Browser::SessionManager.lookup(browser_session_id:)
    assert_equal true, hosts.first.fetch(:host).closed
  end

  test "navigate, get_content, and screenshot dispatch through the stored host" do
    host = FakeHost.new(commands: [], closed: false)
    host_factory = ->(session_id:) { host }

    opened = Fenix::Browser::SessionManager.call(
      action: "open",
      url: "https://example.com",
      host_factory:
    )

    browser_session_id = opened.fetch("browser_session_id")

    navigated = Fenix::Browser::SessionManager.call(
      action: "navigate",
      browser_session_id:,
      url: "https://example.com/docs",
      host_factory:
    )
    content = Fenix::Browser::SessionManager.call(
      action: "get_content",
      browser_session_id:,
      host_factory:
    )
    screenshot = Fenix::Browser::SessionManager.call(
      action: "screenshot",
      browser_session_id:,
      host_factory:
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
      host_factory:
    )
    browser_session_id = opened.fetch("browser_session_id")

    Fenix::Browser::SessionManager.call(
      action: "navigate",
      browser_session_id:,
      url: "https://example.com/docs",
      host_factory:
    )

    listed = Fenix::Browser::SessionManager.call(action: "list", host_factory:)
    info = Fenix::Browser::SessionManager.call(action: "info", browser_session_id:, host_factory:)

    assert_equal browser_session_id, listed.fetch("entries").fetch(0).fetch("browser_session_id")
    assert_equal "https://example.com/docs", listed.fetch("entries").fetch(0).fetch("current_url")
    assert_equal browser_session_id, info.fetch("browser_session_id")
    assert_equal "https://example.com/docs", info.fetch("current_url")
  end
end
