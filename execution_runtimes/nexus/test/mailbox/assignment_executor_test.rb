require "test_helper"

class AssignmentExecutorTest < Minitest::Test
  def test_tool_call_assignments_queue_started_progress_and_complete_events
    store = CybrosNexus::State::Store.open(path: tmp_path("state.sqlite3"))
    outbox = CybrosNexus::Events::Outbox.new(store: store)
    command_host = CybrosNexus::Resources::CommandHost.new(store: store)
    process_registry = CybrosNexus::Resources::ProcessRegistry.new(store: store)
    process_host = CybrosNexus::Resources::ProcessHost.new(store: store, registry: process_registry, outbox: outbox)
    executor = CybrosNexus::Mailbox::AssignmentExecutor.new(
      store: store,
      outbox: outbox,
      command_host: command_host,
      process_host: process_host,
      workdir: tmp_root
    )

    result = executor.call(
      mailbox_item: execution_assignment_mailbox_item(
        task_payload: { "mode" => "tool_call" },
        tool_call: {
          "call_id" => "tool-call-1",
          "tool_name" => "exec_command",
          "arguments" => {
            "command_line" => "printf hello",
          },
        },
        runtime_resource_refs: {
          "command_run" => {
            "command_run_id" => "command-run-1",
            "runtime_owner_id" => "workflow-node-1",
          },
          "tool_invocation" => {
            "tool_invocation_id" => "tool-invocation-1",
          },
        }
      )
    )

    method_ids = outbox.pending.map { |event| event.fetch("payload").fetch("method_id") }

    assert_equal "ok", result.fetch("status")
    assert_equal ["execution_started", "execution_progress", "execution_complete"], method_ids
    assert_equal "tool-call-1", outbox.pending[1].dig("payload", "progress_payload", "tool_invocation_output", "call_id")
    assert_equal "exec_command", outbox.pending[2].dig("payload", "terminal_payload", "tool_invocations", 0, "tool_name")
    assert_equal "completed", outbox.pending[2].dig("payload", "terminal_payload", "tool_invocations", 0, "event")
  ensure
    process_host&.shutdown
    command_host&.shutdown
    store&.close
  end

  def test_failed_assignments_queue_started_and_fail_events
    store = CybrosNexus::State::Store.open(path: tmp_path("state.sqlite3"))
    outbox = CybrosNexus::Events::Outbox.new(store: store)
    command_host = CybrosNexus::Resources::CommandHost.new(store: store)
    process_registry = CybrosNexus::Resources::ProcessRegistry.new(store: store)
    process_host = CybrosNexus::Resources::ProcessHost.new(store: store, registry: process_registry, outbox: outbox)
    executor = CybrosNexus::Mailbox::AssignmentExecutor.new(
      store: store,
      outbox: outbox,
      command_host: command_host,
      process_host: process_host,
      workdir: tmp_root
    )

    result = executor.call(
      mailbox_item: execution_assignment_mailbox_item(
        task_payload: { "mode" => "raise_error" }
      )
    )

    method_ids = outbox.pending.map { |event| event.fetch("payload").fetch("method_id") }

    assert_equal "failed", result.fetch("status")
    assert_equal ["execution_started", "execution_fail"], method_ids
    assert_equal "runtime_error", outbox.pending.last.dig("payload", "terminal_payload", "code")
  ensure
    process_host&.shutdown
    command_host&.shutdown
    store&.close
  end

  private

  def execution_assignment_mailbox_item(task_payload:, tool_call: nil, runtime_resource_refs: {})
    {
      "item_type" => "execution_assignment",
      "item_id" => "mailbox-item-1",
      "protocol_message_id" => "protocol-message-1",
      "logical_work_id" => "logical-work-1",
      "attempt_no" => 1,
      "control_plane" => "execution_runtime",
      "payload" => {
        "request_kind" => "execution_assignment",
        "task" => {
          "agent_task_run_id" => "agent-task-run-1",
          "workflow_run_id" => "workflow-run-1",
          "workflow_node_id" => "workflow-node-1",
          "conversation_id" => "conversation-1",
          "turn_id" => "turn-1",
          "kind" => "turn_step",
        },
        "runtime_context" => {
          "control_plane" => "execution_runtime",
          "logical_work_id" => "logical-work-1",
          "attempt_no" => 1,
        },
        "task_payload" => task_payload,
        "tool_call" => tool_call,
        "runtime_resource_refs" => runtime_resource_refs,
      }.compact,
    }
  end
end
