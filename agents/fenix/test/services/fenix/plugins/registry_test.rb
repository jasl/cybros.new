require "test_helper"

class Fenix::Plugins::RegistryTest < ActiveSupport::TestCase
  test "default registry composes environment tool names from plugin manifests" do
    registry = Fenix::Plugins::Registry.default
    catalog = registry.catalog

    assert_includes registry.manifests.map(&:plugin_id), "system.exec_command"
    assert_includes registry.manifests.map(&:plugin_id), "system.workspace"
    assert_includes registry.manifests.map(&:plugin_id), "system.memory"
    assert_includes catalog.environment_tool_names, "exec_command"
    assert_includes catalog.environment_tool_names, "write_stdin"
    assert_includes catalog.environment_tool_names, "workspace_read"
    assert_includes catalog.environment_tool_names, "workspace_write"
    assert_includes catalog.environment_tool_names, "memory_get"
    assert_includes catalog.environment_tool_names, "memory_search"
    assert_includes catalog.environment_tool_names, "memory_store"
  end
end
