require "test_helper"

class Fenix::Plugins::RegistryTest < ActiveSupport::TestCase
  test "default registry composes environment tool names from plugin manifests" do
    registry = Fenix::Plugins::Registry.default
    catalog = registry.catalog

    assert_includes registry.manifests.map(&:plugin_id), "system.exec_command"
    assert_includes registry.manifests.map(&:plugin_id), "system.workspace"
    assert_includes registry.manifests.map(&:plugin_id), "system.memory"
    assert_includes registry.manifests.map(&:plugin_id), "system.web"
    assert_includes registry.manifests.map(&:plugin_id), "system.browser"
    assert_includes catalog.environment_tool_names, "exec_command"
    assert_includes catalog.environment_tool_names, "write_stdin"
    assert_includes catalog.environment_tool_names, "workspace_read"
    assert_includes catalog.environment_tool_names, "workspace_write"
    assert_includes catalog.environment_tool_names, "memory_get"
    assert_includes catalog.environment_tool_names, "memory_search"
    assert_includes catalog.environment_tool_names, "memory_store"
    assert_includes catalog.environment_tool_names, "web_fetch"
    assert_includes catalog.environment_tool_names, "web_search"
    assert_includes catalog.environment_tool_names, "firecrawl_search"
    assert_includes catalog.environment_tool_names, "firecrawl_scrape"
    assert_includes catalog.environment_tool_names, "browser_open"
    assert_includes catalog.environment_tool_names, "browser_navigate"
    assert_includes catalog.environment_tool_names, "browser_get_content"
    assert_includes catalog.environment_tool_names, "browser_screenshot"
    assert_includes catalog.environment_tool_names, "browser_close"
  end
end
