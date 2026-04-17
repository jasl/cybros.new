require "test_helper"

class Runtime::ExecuteMailboxItemTest < ActiveSupport::TestCase
  RuntimeControlClientDouble = Struct.new(:reported_payloads, keyword_init: true) do
    def report!(payload:)
      reported_payloads << payload.deep_dup
      { "result" => "accepted" }
    end
  end

  test "agent requests are rejected because nexus is execution-runtime-only" do
    client = RuntimeControlClientDouble.new(reported_payloads: [])

    error = assert_raises(Runtime::ExecuteMailboxItem::UnsupportedMailboxItemError) do
      Runtime::ExecuteMailboxItem.call(
        mailbox_item: agent_request_mailbox_item,
        deliver_reports: true,
        control_client: client
      )
    end

    assert_match(/agent_request/, error.message)
    assert_equal [], client.reported_payloads
  end

  test "skills execution assignments emit started and completed terminal reports" do
    client = RuntimeControlClientDouble.new(reported_payloads: [])
    original_load = Skills::Load.method(:call)
    Skills::Load.define_singleton_method(:call) do |skill_name:, repository:|
      {
        "name" => skill_name,
        "scope" => [
          repository.scope_roots.agent_id,
          repository.scope_roots.user_id,
        ],
      }
    end

    result = Runtime::ExecuteMailboxItem.call(
      mailbox_item: execution_assignment_mailbox_item(
        mode: "skills_load",
        task_payload: { "skill_name" => "portable-notes" },
        runtime_context: {
          "agent_id" => "agent-1",
          "user_id" => "user-1",
          "agent_version_id" => "agent-definition-version-1",
        }
      ),
      deliver_reports: true,
      control_client: client
    )

    assert_equal "ok", result.fetch("status")
    assert_equal "portable-notes", result.dig("output", "name")
    assert_equal ["execution_started", "execution_complete"], client.reported_payloads.map { |payload| payload.fetch("method_id") }
    assert_equal 30, client.reported_payloads.first.fetch("expected_duration_seconds")
    assert_equal "portable-notes", client.reported_payloads.last.dig("terminal_payload", "name")
  ensure
    Skills::Load.define_singleton_method(:call, original_load) if original_load
  end

  test "deterministic tool execution assignments emit started and completed terminal reports" do
    client = RuntimeControlClientDouble.new(reported_payloads: [])

    result = Runtime::ExecuteMailboxItem.call(
      mailbox_item: execution_assignment_mailbox_item(
        mode: "deterministic_tool",
        task_payload: { "expression" => "7 + 5" }
      ),
      deliver_reports: true,
      control_client: client
    )

    assert_equal "ok", result.fetch("status")
    assert_equal 12, result.dig("output", "result")
    assert_equal ["execution_started", "execution_complete"], client.reported_payloads.map { |payload| payload.fetch("method_id") }
    assert_equal 30, client.reported_payloads.first.fetch("expected_duration_seconds")
    assert_equal "The calculator returned 12.", client.reported_payloads.last.dig("terminal_payload", "content")
  end

  test "tool-call execution assignments execute through the runtime tool executor" do
    client = RuntimeControlClientDouble.new(reported_payloads: [])

    result = Runtime::ExecuteMailboxItem.call(
      mailbox_item: execution_assignment_mailbox_item(
        mode: "tool_call",
        task_payload: {},
        runtime_context: {
          "agent_version_id" => "agent-definition-version-1",
        },
        tool_call: {
          "call_id" => "tool-call-1",
          "tool_name" => "command_run_list",
          "arguments" => {},
        }
      ),
      deliver_reports: true,
      control_client: client
    )

    assert_equal "ok", result.fetch("status")
    assert_equal ["execution_started", "execution_complete"], client.reported_payloads.map { |payload| payload.fetch("method_id") }
    assert_equal "completed", result.dig("output", "tool_invocations", 0, "event")
    assert_equal "tool-call-1", result.dig("output", "tool_invocations", 0, "call_id")
    assert_equal "command_run_list", result.dig("output", "tool_invocations", 0, "tool_name")
    assert_equal({ "entries" => [] }, result.dig("output", "tool_invocations", 0, "response_payload"))
    assert_equal "Execution runtime completed the requested tool call.", result.dig("output", "output")
  end

  test "skills execution assignments emit started before deterministic scope failures" do
    client = RuntimeControlClientDouble.new(reported_payloads: [])

    result = Runtime::ExecuteMailboxItem.call(
      mailbox_item: execution_assignment_mailbox_item(
        mode: "skills_catalog_list",
        runtime_context: {
          "agent_version_id" => "agent-definition-version-1",
        }
      ),
      deliver_reports: true,
      control_client: client
    )

    assert_equal "failed", result.fetch("status")
    assert_equal ["execution_started", "execution_fail"], client.reported_payloads.map { |payload| payload.fetch("method_id") }
    assert_equal 30, client.reported_payloads.first.fetch("expected_duration_seconds")
    assert_equal "missing_skill_scope", client.reported_payloads.last.dig("terminal_payload", "code")
  end

  test "raise_error execution assignments emit started before a terminal runtime failure" do
    client = RuntimeControlClientDouble.new(reported_payloads: [])

    result = Runtime::ExecuteMailboxItem.call(
      mailbox_item: execution_assignment_mailbox_item(mode: "raise_error"),
      deliver_reports: true,
      control_client: client
    )

    assert_equal "failed", result.fetch("status")
    assert_equal ["execution_started", "execution_fail"], client.reported_payloads.map { |payload| payload.fetch("method_id") }
    assert_equal 30, client.reported_payloads.first.fetch("expected_duration_seconds")
    assert_equal "runtime_error", client.reported_payloads.last.dig("terminal_payload", "code")
    assert_match(/requested execution assignment failure/i, client.reported_payloads.last.dig("terminal_payload", "message"))
  end

  test "unsupported execution assignment dispatch kinds fail with a configuration terminal payload" do
    client = RuntimeControlClientDouble.new(reported_payloads: [])
    original_call = Runtime::Assignments::DispatchMode.method(:call)

    Runtime::Assignments::DispatchMode.define_singleton_method(:call) do |**|
      { "kind" => "unsupported_kind" }
    end

    result = Runtime::ExecuteMailboxItem.call(
      mailbox_item: execution_assignment_mailbox_item(mode: "deterministic_tool"),
      deliver_reports: true,
      control_client: client
    )

    assert_equal "failed", result.fetch("status")
    assert_equal ["execution_started", "execution_fail"], client.reported_payloads.map { |payload| payload.fetch("method_id") }
    assert_equal "unsupported_execution_assignment_dispatch_kind", client.reported_payloads.last.dig("terminal_payload", "code")
    assert_match(/unsupported execution assignment dispatch kind/i, client.reported_payloads.last.dig("terminal_payload", "message"))
  ensure
    Runtime::Assignments::DispatchMode.define_singleton_method(:call, original_call) if original_call
  end

  private

  def execution_assignment_mailbox_item(mode:, task_payload: {}, runtime_context: {}, tool_call: nil, runtime_resource_refs: {})
    {
      "item_type" => "execution_assignment",
      "item_id" => "mailbox-item-execution-assignment-1",
      "protocol_message_id" => "protocol-message-execution-assignment-1",
      "logical_work_id" => "logical-work-execution-assignment-1",
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
        "runtime_context" => runtime_context,
        "task_payload" => {
          "mode" => mode,
        }.merge(task_payload),
        "tool_call" => tool_call,
        "runtime_resource_refs" => runtime_resource_refs,
      },
    }
  end

  def agent_request_mailbox_item
    {
      "item_type" => "agent_request",
      "item_id" => "mailbox-item-agent-request-1",
      "protocol_message_id" => "protocol-message-agent-request-1",
      "logical_work_id" => "agent-request:workflow-node-1",
      "attempt_no" => 1,
      "control_plane" => "execution_runtime",
      "payload" => {
        "request_kind" => "agent_request",
      },
    }
  end
end
