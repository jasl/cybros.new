require "test_helper"

class MemoryFlowTest < ActiveSupport::TestCase
  test "memory_store writes daily memory and memory_search finds it" do
    marker = "remember-#{SecureRandom.hex(6)}"

    store_result = Fenix::Runtime::ExecuteAssignment.call(
      mailbox_item: runtime_assignment_payload(
        mode: "deterministic_tool",
        task_payload: {
          "tool_name" => "memory_store",
          "text" => "Daily note: #{marker}",
          "title" => "daily-note",
        },
        agent_context: default_agent_context.merge(
          "allowed_tool_names" => default_agent_context.fetch("allowed_tool_names") + ["memory_store"]
        )
      )
    )

    store_invocation = store_result.reports.last
      .fetch("terminal_payload")
      .fetch("tool_invocations")
      .fetch(0)

    assert_equal "completed", store_result.status
    assert_match(%r{\A\.fenix/memory/daily/}, store_invocation.dig("response_payload", "memory_path"))
    assert_equal "daily", store_invocation.dig("response_payload", "scope")

    search_result = Fenix::Runtime::ExecuteAssignment.call(
      mailbox_item: runtime_assignment_payload(
        mode: "deterministic_tool",
        task_payload: {
          "tool_name" => "memory_search",
          "query" => marker,
        },
        agent_context: default_agent_context.merge(
          "allowed_tool_names" => default_agent_context.fetch("allowed_tool_names") + ["memory_search"]
        )
      )
    )

    search_invocation = search_result.reports.last
      .fetch("terminal_payload")
      .fetch("tool_invocations")
      .fetch(0)
    matches = search_invocation.dig("response_payload", "matches")

    assert_equal "completed", search_result.status
    assert_equal 1, matches.size
    assert_match(marker, matches.first.fetch("excerpt"))
  end

  test "memory_get returns root memory and conversation-local summary" do
    payload = runtime_assignment_payload(
      mode: "deterministic_tool",
      task_payload: {
        "tool_name" => "memory_get",
        "scope" => "all",
      },
      agent_context: default_agent_context.merge(
        "allowed_tool_names" => default_agent_context.fetch("allowed_tool_names") + ["memory_get"]
      )
    )
    conversation_id = payload.fetch("payload").fetch("conversation_id")
    workspace_root = Fenix::Workspace::Layout.default_root
    layout = Fenix::Workspace::Bootstrap.call(workspace_root:, conversation_id:)
    layout.conversation_summary_file.write("Conversation summary\n")

    result = Fenix::Runtime::ExecuteAssignment.call(mailbox_item: payload)

    invocation = result.reports.last
      .fetch("terminal_payload")
      .fetch("tool_invocations")
      .fetch(0)

    assert_equal "completed", result.status
    assert_equal "# Fenix root memory\n", invocation.dig("response_payload", "root_memory")
    assert_equal "Conversation summary\n", invocation.dig("response_payload", "conversation_summary")
  end
end
