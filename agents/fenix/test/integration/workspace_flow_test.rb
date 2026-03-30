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
end
