require "test_helper"

class ConversationRuntime::BuildSafeActivitySummaryTest < ActiveSupport::TestCase
  test "summarizes a completed shell command generically" do
    summary = ConversationRuntime::BuildSafeActivitySummary.call(
      activity_kind: "command",
      command_line: "cd /workspace/game-2048 && npm test && npm run build",
      lifecycle_state: "completed"
    )

    assert_equal "A shell command finished in /workspace/game-2048", summary.fetch("summary")
    assert_equal "Shell command finished.", summary.fetch("detail")
    assert_equal "runtime", summary.fetch("phase")
    assert_equal "command", summary.fetch("work_type")
    assert_equal "/workspace/game-2048", summary.fetch("path_summary")
    assert_equal true, summary.fetch("user_visible")
  end

  test "summarizes a running shell command generically" do
    summary = ConversationRuntime::BuildSafeActivitySummary.call(
      activity_kind: "command",
      command_line: "cd /workspace/game-2048 && npm run preview",
      lifecycle_state: "running"
    )

    assert_equal "A shell command is running in /workspace/game-2048", summary.fetch("summary")
    assert_equal "Shell command is still running.", summary.fetch("detail")
    assert_equal "runtime", summary.fetch("phase")
    assert_equal "command", summary.fetch("work_type")
  end

  test "summarizes a running process generically" do
    summary = ConversationRuntime::BuildSafeActivitySummary.call(
      activity_kind: "process",
      command_line: "cd /workspace/game-2048 && npm run dev -- --host 0.0.0.0 --port 4173",
      lifecycle_state: "running"
    )

    assert_equal "A process is running in /workspace/game-2048", summary.fetch("summary")
    assert_equal "Process is still running.", summary.fetch("detail")
    assert_equal "runtime", summary.fetch("phase")
    assert_equal "process", summary.fetch("work_type")
  end

  test "preserves the shell command working directory without inferring scaffolding semantics" do
    summary = ConversationRuntime::BuildSafeActivitySummary.call(
      activity_kind: "command",
      command_line: "cd /workspace && npm create vite@latest game-2048 -- --template react-ts",
      lifecycle_state: "completed"
    )

    assert_equal "A shell command finished in /workspace", summary.fetch("summary")
    assert_equal "runtime", summary.fetch("phase")
    assert_equal "command", summary.fetch("work_type")
  end

  test "preserves the shell command working directory without inferring dependency semantics" do
    summary = ConversationRuntime::BuildSafeActivitySummary.call(
      activity_kind: "command",
      command_line: "cd /workspace/game-2048 && npm install && npm install -D vitest jsdom",
      lifecycle_state: "completed"
    )

    assert_equal "A shell command finished in /workspace/game-2048", summary.fetch("summary")
    assert_equal "runtime", summary.fetch("phase")
    assert_equal "command", summary.fetch("work_type")
  end

  test "preserves the shell command working directory without inferring editing semantics" do
    summary = ConversationRuntime::BuildSafeActivitySummary.call(
      activity_kind: "command",
      command_line: "cd /workspace/game-2048 && cat <<'EOF' > src/App.tsx\nexport default function App() {}\nEOF",
      lifecycle_state: "completed"
    )

    assert_equal "A shell command finished in /workspace/game-2048", summary.fetch("summary")
    assert_equal "Shell command finished.", summary.fetch("detail")
    assert_equal "runtime", summary.fetch("phase")
    assert_equal "command", summary.fetch("work_type")
  end

  test "preserves the shell command working directory without inferring inspection semantics" do
    summary = ConversationRuntime::BuildSafeActivitySummary.call(
      activity_kind: "command",
      command_line: "cd /workspace/game-2048 && ls src",
      lifecycle_state: "completed"
    )

    assert_equal "A shell command finished in /workspace/game-2048", summary.fetch("summary")
    assert_equal "Shell command finished.", summary.fetch("detail")
    assert_equal "runtime", summary.fetch("phase")
    assert_equal "command", summary.fetch("work_type")
  end
end
