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

  test "memory operator helpers list daily notes and compact conversation summary" do
    conversation_id = "conversation-#{SecureRandom.uuid}"
    append_payload = runtime_assignment_payload(
      mode: "deterministic_tool",
      conversation_id:,
      task_payload: {
        "tool_name" => "memory_append_daily",
        "text" => "operator daily note",
        "title" => "operator-note",
      },
      agent_context: default_agent_context.merge(
        "allowed_tool_names" => default_agent_context.fetch("allowed_tool_names") + %w[memory_append_daily memory_list memory_compact_summary memory_get]
      )
    )

    append_result = Fenix::Runtime::ExecuteAssignment.call(mailbox_item: append_payload)
    append_invocation = append_result.reports.last
      .fetch("terminal_payload")
      .fetch("tool_invocations")
      .fetch(0)

    assert_equal "completed", append_result.status
    assert_match(%r{\A\.fenix/memory/daily/}, append_invocation.dig("response_payload", "memory_path"))

    list_result = Fenix::Runtime::ExecuteAssignment.call(
      mailbox_item: runtime_assignment_payload(
        mode: "deterministic_tool",
        conversation_id:,
        task_payload: {
          "tool_name" => "memory_list",
        },
        agent_context: default_agent_context.merge(
          "allowed_tool_names" => default_agent_context.fetch("allowed_tool_names") + ["memory_list"]
        )
      )
    )

    list_invocation = list_result.reports.last
      .fetch("terminal_payload")
      .fetch("tool_invocations")
      .fetch(0)

    assert_equal "completed", list_result.status
    assert list_invocation.dig("response_payload", "entries").any? { |entry| entry.fetch("path") == append_invocation.dig("response_payload", "memory_path") }

    compact_result = Fenix::Runtime::ExecuteAssignment.call(
      mailbox_item: runtime_assignment_payload(
        mode: "deterministic_tool",
        conversation_id:,
        task_payload: {
          "tool_name" => "memory_compact_summary",
          "text" => "Compact operator summary",
          "scope" => "conversation",
        },
        agent_context: default_agent_context.merge(
          "allowed_tool_names" => default_agent_context.fetch("allowed_tool_names") + %w[memory_compact_summary memory_get]
        )
      )
    )

    compact_invocation = compact_result.reports.last
      .fetch("terminal_payload")
      .fetch("tool_invocations")
      .fetch(0)

    assert_equal "completed", compact_result.status
    assert_match(%r{\.fenix/conversations/.+/context/summary\.md\z}, compact_invocation.dig("response_payload", "memory_path"))

    get_result = Fenix::Runtime::ExecuteAssignment.call(
      mailbox_item: runtime_assignment_payload(
        mode: "deterministic_tool",
        conversation_id:,
        task_payload: {
          "tool_name" => "memory_get",
          "scope" => "conversation",
        },
        agent_context: default_agent_context.merge(
          "allowed_tool_names" => default_agent_context.fetch("allowed_tool_names") + ["memory_get"]
        )
      )
    )

    get_invocation = get_result.reports.last
      .fetch("terminal_payload")
      .fetch("tool_invocations")
      .fetch(0)

    assert_equal "completed", get_result.status
    assert_equal "Compact operator summary", get_invocation.dig("response_payload", "conversation_summary")
  end
end
