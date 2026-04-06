require "test_helper"

class ConversationRuntime::BuildSafeActivitySummaryTest < ActiveSupport::TestCase
  test "classifies a combined npm test and build command as the test-and-build check" do
    summary = ConversationRuntime::BuildSafeActivitySummary.call(
      activity_kind: "command",
      command_line: "cd /workspace/game-2048 && npm test && npm run build",
      lifecycle_state: "completed"
    )

    assert_equal "Ran the test-and-build check in /workspace/game-2048", summary.fetch("summary")
    assert_equal "Command completed successfully.", summary.fetch("detail")
    assert_equal "validate", summary.fetch("phase")
    assert_equal "verification", summary.fetch("work_type")
    assert_equal "/workspace/game-2048", summary.fetch("path_summary")
    assert_equal true, summary.fetch("user_visible")
  end

  test "classifies a preview command as starting the preview server" do
    summary = ConversationRuntime::BuildSafeActivitySummary.call(
      activity_kind: "command",
      command_line: "cd /workspace/game-2048 && npm run preview",
      lifecycle_state: "running"
    )

    assert_equal "Starting the preview server in /workspace/game-2048", summary.fetch("summary")
    assert_equal "Command is still running.", summary.fetch("detail")
    assert_equal "validate", summary.fetch("phase")
    assert_equal "preview", summary.fetch("work_type")
  end

  test "classifies long heredoc file writes as editing game files" do
    summary = ConversationRuntime::BuildSafeActivitySummary.call(
      activity_kind: "command",
      command_line: "cd /workspace/game-2048 && cat <<'EOF' > src/App.tsx\nexport default function App() {}\nEOF",
      lifecycle_state: "completed"
    )

    assert_equal "Edited game files in /workspace/game-2048", summary.fetch("summary")
    assert_equal "Command completed successfully.", summary.fetch("detail")
    assert_equal "build", summary.fetch("phase")
    assert_equal "editing", summary.fetch("work_type")
  end

  test "classifies generic directory inspection commands as inspecting the workspace" do
    summary = ConversationRuntime::BuildSafeActivitySummary.call(
      activity_kind: "command",
      command_line: "cd /workspace/game-2048 && ls src",
      lifecycle_state: "completed"
    )

    assert_equal "Inspected the workspace in /workspace/game-2048", summary.fetch("summary")
    assert_equal "Command completed successfully.", summary.fetch("detail")
    assert_equal "plan", summary.fetch("phase")
    assert_equal "inspection", summary.fetch("work_type")
  end
end
