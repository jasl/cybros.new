require "test_helper"

class BrowserHostTest < Minitest::Test
  FakeSessionHost = Struct.new(:commands, :closed, keyword_init: true) do
    def dispatch(command:, arguments:)
      commands << { "command" => command, "arguments" => arguments }

      case command
      when "open"
        { "current_url" => arguments["url"] }
      when "navigate"
        { "current_url" => arguments["url"] }
      when "get_content"
        { "current_url" => "https://example.com/docs", "content" => "Example page" }
      when "screenshot"
        { "current_url" => "https://example.com/docs", "mime_type" => "image/png", "image_base64" => "cG5n" }
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

  def test_capability_gating_rejects_browser_sessions_when_unavailable
    host = CybrosNexus::Browser::Host.new(
      session_registry: CybrosNexus::Browser::SessionRegistry.new,
      capability_probe: {
        "available" => false,
        "reason" => "playwright_missing",
      }
    )

    error = assert_raises(CybrosNexus::Browser::Host::ValidationError) do
      host.open(url: "https://example.com", runtime_owner_id: "task-1")
    end

    assert_includes error.message, "playwright_missing"
  end

  def test_session_lifecycle_and_manifest_flags_follow_browser_capability
    host = CybrosNexus::Browser::Host.new(
      session_registry: CybrosNexus::Browser::SessionRegistry.new,
      capability_probe: {
        "available" => true,
        "reason" => nil,
      },
      host_factory: lambda do |session_id:|
        FakeSessionHost.new(commands: [], closed: false)
      end
    )

    opened = host.open(url: "https://example.com", runtime_owner_id: "task-1")
    browser_session_id = opened.fetch("browser_session_id")
    navigated = host.navigate(browser_session_id: browser_session_id, url: "https://example.com/docs", runtime_owner_id: "task-1")
    content = host.get_content(browser_session_id: browser_session_id, runtime_owner_id: "task-1")
    screenshot = host.screenshot(browser_session_id: browser_session_id, full_page: false, runtime_owner_id: "task-1")
    listed = host.list(runtime_owner_id: "task-1")
    info = host.session_info(browser_session_id: browser_session_id, runtime_owner_id: "task-1")
    closed = host.close(browser_session_id: browser_session_id, runtime_owner_id: "task-1")

    config = CybrosNexus::Config.load(
      env: {
        "CORE_MATRIX_BASE_URL" => "https://core-matrix.example.test",
        "NEXUS_HOME_ROOT" => tmp_path("nexus-home"),
      }
    )
    manifest = CybrosNexus::Session::RuntimeManifest.new(
      config: config,
      browser_available: host.available?,
      browser_unavailable_reason: host.unavailable_reason
    )

    assert_equal "https://example.com", opened.fetch("current_url")
    assert_equal "https://example.com/docs", navigated.fetch("current_url")
    assert_equal "Example page", content.fetch("content")
    assert_equal "image/png", screenshot.fetch("mime_type")
    assert_equal [browser_session_id], listed.fetch("entries").map { |entry| entry.fetch("browser_session_id") }
    assert_equal browser_session_id, info.fetch("browser_session_id")
    assert_equal true, closed.fetch("closed")
    assert_equal true, manifest.version_package.dig("capability_payload", "runtime_foundation", "browser_automation_available")
    assert_equal true, manifest.version_package.dig("capability_payload", "runtime_foundation", "attachment_input_refresh_available")
    assert_equal true, manifest.version_package.dig("capability_payload", "runtime_foundation", "attachment_output_publish_available")
    assert_includes manifest.version_package.fetch("tool_catalog").map { |entry| entry.fetch("tool_name") }, "browser_open"
  end
end
