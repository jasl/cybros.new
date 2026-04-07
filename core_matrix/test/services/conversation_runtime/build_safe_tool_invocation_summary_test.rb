require "test_helper"

class ConversationRuntime::BuildSafeToolInvocationSummaryTest < ActiveSupport::TestCase
  test "summarizes workspace inspection without leaking the tool name" do
    summary = ConversationRuntime::BuildSafeToolInvocationSummary.call(
      tool_name: "workspace_tree",
      arguments: { "path" => "/workspace/game-2048" }
    )

    assert_equal "Inspect the workspace tree", summary.fetch("title")
    assert_equal "Inspected the workspace tree", summary.fetch("summary")
    assert_equal "Started inspecting the workspace tree.", summary.fetch("started_summary")
    assert_includes summary.fetch("detail"), "/workspace/game-2048"
    refute_match(/workspace_tree/i, summary.to_json)
  end

  test "summarizes stdin writes using generic shell command wording" do
    summary = ConversationRuntime::BuildSafeToolInvocationSummary.call(
      tool_name: "write_stdin",
      command_summary: "the test-and-build check in /workspace/game-2048",
      command_metadata: {
        "summary" => "Running the test-and-build check in /workspace/game-2048",
        "path_summary" => "/workspace/game-2048",
      }
    )

    assert_equal "Check progress on the shell command in /workspace/game-2048", summary.fetch("title")
    assert_equal "Checked progress on the shell command in /workspace/game-2048", summary.fetch("summary")
    assert_equal "Started checking progress on the shell command in /workspace/game-2048.", summary.fetch("started_summary")
    refute_match(/write_stdin/i, summary.to_json)
    refute_match(/Respond to|Sent input to/i, summary.to_json)
  end

  test "summarizes browser content capture without leaking the raw tool name" do
    summary = ConversationRuntime::BuildSafeToolInvocationSummary.call(
      tool_name: "browser_get_content"
    )

    assert_equal "Capture browser content", summary.fetch("title")
    assert_equal "Captured browser content", summary.fetch("summary")
    assert_equal "Started capturing browser content.", summary.fetch("started_summary")
    refute_match(/browser_get_content/i, summary.to_json)
  end

  test "summarizes workspace search without leaking the raw tool name" do
    summary = ConversationRuntime::BuildSafeToolInvocationSummary.call(
      tool_name: "workspace_find",
      arguments: {
        "path" => "/workspace/game-2048",
        "query" => "game over",
      }
    )

    assert_equal "Search workspace files", summary.fetch("title")
    assert_equal "Searched workspace files", summary.fetch("summary")
    assert_equal "Started searching workspace files.", summary.fetch("started_summary")
    assert_includes summary.fetch("detail"), "game over"
    refute_match(/workspace_find/i, summary.to_json)
  end

  test "summarizes command run lists without leaking the raw tool name" do
    summary = ConversationRuntime::BuildSafeToolInvocationSummary.call(
      tool_name: "command_run_list"
    )

    assert_equal "Review shell command status", summary.fetch("title")
    assert_equal "Reviewed shell command status", summary.fetch("summary")
    assert_equal "Started reviewing shell command status.", summary.fetch("started_summary")
    refute_match(/command_run_list/i, summary.to_json)
  end

  test "summarizes browser opens without leaking the raw tool name" do
    summary = ConversationRuntime::BuildSafeToolInvocationSummary.call(
      tool_name: "browser_open",
      arguments: { "url" => "http://127.0.0.1:4173" }
    )

    assert_equal "Open the browser at http://127.0.0.1:4173", summary.fetch("title")
    assert_equal "Opened the browser at http://127.0.0.1:4173", summary.fetch("summary")
    assert_equal "Started opening the browser at http://127.0.0.1:4173.", summary.fetch("started_summary")
    refute_match(/browser_open/i, summary.to_json)
  end

  test "summarizes command waits using generic shell command wording" do
    summary = ConversationRuntime::BuildSafeToolInvocationSummary.call(
      tool_name: "command_run_wait",
      command_summary: "the preview server in /workspace/game-2048",
      command_metadata: {
        "summary" => "Starting the preview server in /workspace/game-2048",
        "path_summary" => "/workspace/game-2048",
      }
    )

    assert_equal "Wait for the shell command in /workspace/game-2048", summary.fetch("title")
    assert_equal "Waiting for the shell command in /workspace/game-2048", summary.fetch("summary")
    assert_equal "Started waiting for the shell command in /workspace/game-2048.", summary.fetch("started_summary")
    refute_match(/command_run_wait/i, summary.to_json)
  end

  test "summarizes command waits without inspection-specific phrasing" do
    summary = ConversationRuntime::BuildSafeToolInvocationSummary.call(
      tool_name: "command_run_wait",
      command_summary: "the workspace in /workspace",
      command_metadata: {
        "summary" => "Inspecting the workspace in /workspace",
        "path_summary" => "/workspace",
      }
    )

    assert_equal "Wait for the shell command in /workspace", summary.fetch("title")
    assert_equal "Waiting for the shell command in /workspace", summary.fetch("summary")
    assert_equal "Started waiting for the shell command in /workspace.", summary.fetch("started_summary")
  end

  test "summarizes stdin writes that close a command session with the completed command result" do
    summary = ConversationRuntime::BuildSafeToolInvocationSummary.call(
      tool_name: "write_stdin",
      response_payload: {
        "session_closed" => true,
        "command_run_id" => "cmd_123",
      },
      command_summary: "The shell command completed in /workspace/game-2048",
      command_metadata: {
        "summary" => "The shell command completed in /workspace/game-2048",
        "path_summary" => "/workspace/game-2048",
      }
    )

    assert_equal "The shell command completed in /workspace/game-2048", summary.fetch("title")
    assert_equal "The shell command completed in /workspace/game-2048", summary.fetch("summary")
    assert_equal "Started collecting the final result from the shell command in /workspace/game-2048.", summary.fetch("started_summary")
    refute_match(/Respond to|Sent input to/i, summary.to_json)
  end

  test "summarizes command output reads using the referenced command purpose" do
    summary = ConversationRuntime::BuildSafeToolInvocationSummary.call(
      tool_name: "command_run_read_output",
      command_summary: "the test run in /workspace/game-2048"
    )

    assert_equal "Review output from the test run in /workspace/game-2048", summary.fetch("title")
    assert_equal "Reviewed output from the test run in /workspace/game-2048", summary.fetch("summary")
    assert_equal "Started reviewing output from the test run in /workspace/game-2048.", summary.fetch("started_summary")
    refute_match(/command_run_read_output/i, summary.to_json)
  end

  test "summarizes subagent coordination tools without leaking the raw tool name" do
    summary = ConversationRuntime::BuildSafeToolInvocationSummary.call(
      tool_name: "subagent_send"
    )

    assert_equal "Message a child task", summary.fetch("title")
    assert_equal "Messaged a child task", summary.fetch("summary")
    assert_equal "Started messaging a child task.", summary.fetch("started_summary")
    refute_match(/subagent_send/i, summary.to_json)
  end
end
