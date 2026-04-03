require "test_helper"

class Fenix::Operator::CatalogTest < ActiveSupport::TestCase
  test "groups execution tools into operator families" do
    registry = Fenix::Plugins::Registry.default
    groups = Fenix::Operator::Catalog.new(tool_catalog: registry.catalog.execution_tool_catalog).groups

    assert_equal "Workspace", groups.fetch("workspace").fetch("label")
    assert_equal %w[workspace_read workspace_write workspace_tree workspace_stat workspace_find], groups.fetch("workspace").fetch("tool_names")
    assert_equal ["workspace_path"], groups.fetch("workspace").fetch("resource_identity_kinds")

    assert_equal "Command Run", groups.fetch("command_run").fetch("label")
    assert_includes groups.fetch("command_run").fetch("tool_names"), "exec_command"
    assert_includes groups.fetch("command_run").fetch("tool_names"), "write_stdin"

    assert_equal "Browser Session", groups.fetch("browser_session").fetch("label")
    assert_includes groups.fetch("browser_session").fetch("tool_names"), "browser_open"
    assert_includes groups.fetch("process_run").fetch("tool_names"), "process_exec"
  end

  test "decorates tool entries with operator metadata defaults" do
    entry = Fenix::Plugins::Registry.default.catalog.execution_tool_catalog.find { |tool| tool.fetch("tool_name") == "exec_command" }

    assert_equal "command_run", entry.fetch("operator_group")
    assert_equal "Command Run", entry.fetch("operator_group_label")
    assert_equal "command_run", entry.fetch("resource_identity_kind")
    assert_equal true, entry.fetch("mutates_state")
    assert_equal true, entry.fetch("supports_streaming_output")
  end
end
