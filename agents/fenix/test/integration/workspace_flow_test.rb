require "test_helper"

class WorkspaceFlowTest < ActiveSupport::TestCase
  test "workspace_write stores content under the mounted root and workspace_read returns it" do
    relative_path = "notes/#{SecureRandom.hex(4)}.md"
    contents = "hello workspace\n"

    write_result = Fenix::Runtime::ExecuteAssignment.call(
      mailbox_item: runtime_assignment_payload(
        mode: "deterministic_tool",
        task_payload: {
          "tool_name" => "workspace_write",
          "path" => relative_path,
          "content" => contents,
        },
        agent_context: default_agent_context.merge(
          "allowed_tool_names" => default_agent_context.fetch("allowed_tool_names") + ["workspace_write"]
        )
      )
    )

    write_invocation = write_result.reports.last
      .fetch("terminal_payload")
      .fetch("tool_invocations")
      .fetch(0)

    assert_equal "completed", write_result.status
    assert_equal relative_path, write_invocation.dig("response_payload", "path")
    assert_equal contents.bytesize, write_invocation.dig("response_payload", "bytes_written")
    assert_equal contents, Fenix::Workspace::Layout.default_root.then { |root| Pathname.new(root).join(relative_path).read }

    read_result = Fenix::Runtime::ExecuteAssignment.call(
      mailbox_item: runtime_assignment_payload(
        mode: "deterministic_tool",
        task_payload: {
          "tool_name" => "workspace_read",
          "path" => relative_path,
        },
        agent_context: default_agent_context.merge(
          "allowed_tool_names" => default_agent_context.fetch("allowed_tool_names") + ["workspace_read"]
        )
      )
    )

    read_invocation = read_result.reports.last
      .fetch("terminal_payload")
      .fetch("tool_invocations")
      .fetch(0)

    assert_equal "completed", read_result.status
    assert_equal "Workspace file #{relative_path}:\n#{contents}", read_result.output
    assert_equal contents, read_invocation.dig("response_payload", "file_content")
    assert_equal contents.bytesize, read_invocation.dig("response_payload", "bytes_read")
  end

  test "workspace tools reject paths outside the mounted root" do
    result = Fenix::Runtime::ExecuteAssignment.call(
      mailbox_item: runtime_assignment_payload(
        mode: "deterministic_tool",
        task_payload: {
          "tool_name" => "workspace_read",
          "path" => "../secrets.txt",
        },
        agent_context: default_agent_context.merge(
          "allowed_tool_names" => default_agent_context.fetch("allowed_tool_names") + ["workspace_read"]
        )
      )
    )

    failed_invocation = result.error.fetch("tool_invocations").fetch(0)

    assert_equal "failed", result.status
    assert_equal "runtime_error", result.error.fetch("failure_kind")
    assert_match(/outside the workspace root/, result.error.fetch("last_error_summary"))
    assert_equal "workspace_read", failed_invocation.fetch("tool_name")
    assert_equal "validation_error", failed_invocation.dig("error_payload", "code")
  end

  test "workspace_tree, workspace_stat, and workspace_find expose workspace metadata" do
    workspace_root = Pathname.new(Fenix::Workspace::Layout.default_root)
    relative_path = "notes/operator-#{SecureRandom.hex(4)}.md"
    full_path = workspace_root.join(relative_path)
    FileUtils.mkdir_p(full_path.dirname)
    full_path.write("operator workspace\n")

    tree_result = Fenix::Runtime::ExecuteAssignment.call(
      mailbox_item: runtime_assignment_payload(
        mode: "deterministic_tool",
        task_payload: {
          "tool_name" => "workspace_tree",
          "path" => "notes",
        },
        agent_context: default_agent_context.merge(
          "allowed_tool_names" => default_agent_context.fetch("allowed_tool_names") + %w[workspace_tree workspace_stat workspace_find]
        )
      )
    )

    tree_invocation = tree_result.reports.last
      .fetch("terminal_payload")
      .fetch("tool_invocations")
      .fetch(0)

    assert_equal "completed", tree_result.status
    assert tree_invocation.dig("response_payload", "entries").any? { |entry| entry.fetch("path") == relative_path }

    stat_result = Fenix::Runtime::ExecuteAssignment.call(
      mailbox_item: runtime_assignment_payload(
        mode: "deterministic_tool",
        task_payload: {
          "tool_name" => "workspace_stat",
          "path" => relative_path,
        },
        agent_context: default_agent_context.merge(
          "allowed_tool_names" => default_agent_context.fetch("allowed_tool_names") + ["workspace_stat"]
        )
      )
    )

    stat_invocation = stat_result.reports.last
      .fetch("terminal_payload")
      .fetch("tool_invocations")
      .fetch(0)

    assert_equal "completed", stat_result.status
    assert_equal "file", stat_invocation.dig("response_payload", "node_type")
    assert_equal "operator workspace\n".bytesize, stat_invocation.dig("response_payload", "size_bytes")

    find_result = Fenix::Runtime::ExecuteAssignment.call(
      mailbox_item: runtime_assignment_payload(
        mode: "deterministic_tool",
        task_payload: {
          "tool_name" => "workspace_find",
          "query" => "operator-",
        },
        agent_context: default_agent_context.merge(
          "allowed_tool_names" => default_agent_context.fetch("allowed_tool_names") + ["workspace_find"]
        )
      )
    )

    find_invocation = find_result.reports.last
      .fetch("terminal_payload")
      .fetch("tool_invocations")
      .fetch(0)

    assert_equal "completed", find_result.status
    assert find_invocation.dig("response_payload", "matches").any? { |entry| entry.fetch("path") == relative_path }
  end
end
