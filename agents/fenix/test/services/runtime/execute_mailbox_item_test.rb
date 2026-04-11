require "test_helper"
require "tmpdir"

class Runtime::ExecuteMailboxItemTest < ActiveSupport::TestCase
  RuntimeControlClientDouble = Struct.new(:reported_payloads, keyword_init: true) do
    def report!(payload:)
      reported_payloads << payload.deep_dup
      { "result" => "accepted" }
    end
  end

  test "prepare_round agent requests emit a completed terminal report" do
    client = RuntimeControlClientDouble.new(reported_payloads: [])

    Dir.mktmpdir("fenix-workspace-") do |workspace_root|
      Pathname.new(workspace_root).join("AGENTS.md").write("Stay inside agents/fenix unless the task explicitly spans projects.\n")

      result = Runtime::ExecuteMailboxItem.call(
        mailbox_item: prepare_round_mailbox_item(workspace_root: workspace_root),
        deliver_reports: true,
        control_client: client
      )

      assert_equal "ok", result.fetch("status")
      assert_equal ["agent_completed"], client.reported_payloads.map { |payload| payload.fetch("method_id") }
      assert_equal "prepare_round", client.reported_payloads.last.fetch("request_kind")
      assert_equal "ok", client.reported_payloads.last.dig("response_payload", "status")
      assert_equal %w[compact_context exec_command], client.reported_payloads.last.dig("response_payload", "visible_tool_names")
    end
  end

  test "prepare_round terminal report matches the shared contract fixture" do
    client = RuntimeControlClientDouble.new(reported_payloads: [])
    mailbox_item = JSON.parse(
      File.read(
        Rails.root.join("..", "..", "shared", "fixtures", "contracts", "core_matrix_fenix_prepare_round_mailbox_item.json")
      )
    )

    result = Runtime::ExecuteMailboxItem.call(
      mailbox_item: mailbox_item,
      deliver_reports: true,
      control_client: client
    )

    assert_equal "ok", result.fetch("status")
    assert_equal prepare_round_report_contract_fixture, normalize_prepare_round_report(client.reported_payloads.last)
  end

  test "execute_tool agent requests emit a completed terminal report" do
    client = RuntimeControlClientDouble.new(reported_payloads: [])

    result = Runtime::ExecuteMailboxItem.call(
      mailbox_item: execute_tool_mailbox_item(
        allowed_tool_names: %w[calculator]
      ),
      deliver_reports: true,
      control_client: client
    )

    assert_equal "ok", result.fetch("status")
    assert_equal ["agent_completed"], client.reported_payloads.map { |payload| payload.fetch("method_id") }
    assert_equal "execute_tool", client.reported_payloads.last.fetch("request_kind")
    assert_equal "ok", client.reported_payloads.last.dig("response_payload", "status")
    assert_equal "calculator", client.reported_payloads.last.dig("response_payload", "tool_call", "tool_name")
    assert_equal 4, client.reported_payloads.last.dig("response_payload", "result", "value")
  end

  test "execute_tool terminal report matches the shared contract fixture" do
    client = RuntimeControlClientDouble.new(reported_payloads: [])
    mailbox_item = JSON.parse(
      File.read(
        Rails.root.join("..", "..", "shared", "fixtures", "contracts", "core_matrix_fenix_execute_tool_mailbox_item.json")
      )
    )

    result = Runtime::ExecuteMailboxItem.call(
      mailbox_item: mailbox_item,
      deliver_reports: true,
      control_client: client
    )

    assert_equal "ok", result.fetch("status")
    assert_equal execute_tool_report_contract_fixture, normalize_execute_tool_report(client.reported_payloads.last)
  end

  test "execute_tool failures emit a failed terminal report" do
    client = RuntimeControlClientDouble.new(reported_payloads: [])

    result = Runtime::ExecuteMailboxItem.call(
      mailbox_item: execute_tool_mailbox_item(
        allowed_tool_names: []
      ),
      deliver_reports: true,
      control_client: client
    )

    assert_equal "failed", result.fetch("status")
    assert_equal ["agent_failed"], client.reported_payloads.map { |payload| payload.fetch("method_id") }
    assert_equal "execute_tool", client.reported_payloads.last.fetch("request_kind")
    assert_equal "tool_not_allowed", client.reported_payloads.last.dig("error_payload", "code")
  end

  test "execute_tool rejects execution-runtime-backed tools" do
    client = RuntimeControlClientDouble.new(reported_payloads: [])

    result = Runtime::ExecuteMailboxItem.call(
      mailbox_item: execute_tool_mailbox_item(
        allowed_tool_names: %w[process_exec],
        tool_name: "process_exec",
        arguments: {
          "command_line" => "sleep 1",
        }
      ),
      deliver_reports: true,
      control_client: client
    )

    assert_equal "failed", result.fetch("status")
    assert_equal ["agent_failed"], client.reported_payloads.map { |payload| payload.fetch("method_id") }
    assert_equal "unsupported_tool", client.reported_payloads.last.dig("error_payload", "code")
  end

  test "supervision_status_refresh agent requests emit a completed terminal report" do
    client = RuntimeControlClientDouble.new(reported_payloads: [])

    result = Runtime::ExecuteMailboxItem.call(
      mailbox_item: supervision_mailbox_item(request_kind: "supervision_status_refresh"),
      deliver_reports: true,
      control_client: client
    )

    assert_equal "ok", result.fetch("status")
    assert_equal ["agent_completed"], client.reported_payloads.map { |payload| payload.fetch("method_id") }
    assert_equal "supervision_status_refresh", client.reported_payloads.last.fetch("request_kind")
    assert_equal "supervision_status_refresh", client.reported_payloads.last.dig("response_payload", "handled_request_kind")
    assert_equal "status_refresh_acknowledged", client.reported_payloads.last.dig("response_payload", "control_outcome", "outcome_kind")
  end

  test "supervision_guidance agent requests emit a completed terminal report" do
    client = RuntimeControlClientDouble.new(reported_payloads: [])

    result = Runtime::ExecuteMailboxItem.call(
      mailbox_item: supervision_mailbox_item(request_kind: "supervision_guidance"),
      deliver_reports: true,
      control_client: client
    )

    assert_equal "ok", result.fetch("status")
    assert_equal ["agent_completed"], client.reported_payloads.map { |payload| payload.fetch("method_id") }
    assert_equal "supervision_guidance", client.reported_payloads.last.fetch("request_kind")
    assert_equal "supervision_guidance", client.reported_payloads.last.dig("response_payload", "handled_request_kind")
    assert_equal "guidance_acknowledged", client.reported_payloads.last.dig("response_payload", "control_outcome", "outcome_kind")
    assert_equal "Stop and summarize.", client.reported_payloads.last.dig("response_payload", "control_outcome", "content")
  end

  test "supervision_guidance terminal report matches the shared contract fixture" do
    client = RuntimeControlClientDouble.new(reported_payloads: [])
    mailbox_item = JSON.parse(
      File.read(
        Rails.root.join("..", "..", "shared", "fixtures", "contracts", "core_matrix_fenix_supervision_guidance_mailbox_item.json")
      )
    )

    result = Runtime::ExecuteMailboxItem.call(
      mailbox_item: mailbox_item,
      deliver_reports: true,
      control_client: client
    )

    assert_equal "ok", result.fetch("status")
    assert_equal supervision_guidance_report_contract_fixture, normalize_supervision_guidance_report(client.reported_payloads.last)
  end

  test "supervision_guidance without content emits a failed terminal report" do
    client = RuntimeControlClientDouble.new(reported_payloads: [])
    mailbox_item = supervision_mailbox_item(request_kind: "supervision_guidance")
    mailbox_item.fetch("payload").delete("content")

    result = Runtime::ExecuteMailboxItem.call(
      mailbox_item: mailbox_item,
      deliver_reports: true,
      control_client: client
    )

    assert_equal "failed", result.fetch("status")
    assert_equal ["agent_failed"], client.reported_payloads.map { |payload| payload.fetch("method_id") }
    assert_equal "invalid_conversation_control_request", client.reported_payloads.last.dig("error_payload", "code")
  end

  test "execution assignments are rejected because fenix is agent-only" do
    client = RuntimeControlClientDouble.new(reported_payloads: [])

    error = assert_raises(Runtime::ExecuteMailboxItem::UnsupportedMailboxItemError) do
      Runtime::ExecuteMailboxItem.call(
        mailbox_item: execution_assignment_mailbox_item(
          mode: "deterministic_tool",
          task_payload: { "expression" => "7 + 5" }
        ),
        deliver_reports: true,
        control_client: client
      )
    end

    assert_match(/execution_assignment/, error.message)
    assert_equal [], client.reported_payloads
  end

  private

  def execution_assignment_mailbox_item(mode:, task_payload: {}, runtime_context: {})
    {
      "item_type" => "execution_assignment",
      "item_id" => "mailbox-item-execution-assignment-1",
      "protocol_message_id" => "protocol-message-execution-assignment-1",
      "logical_work_id" => "logical-work-execution-assignment-1",
      "attempt_no" => 1,
      "control_plane" => "agent",
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
      },
    }
  end

  def prepare_round_mailbox_item(workspace_root:)
    {
      "item_type" => "agent_request",
      "item_id" => "mailbox-item-prepare-round-1",
      "protocol_message_id" => "protocol-message-prepare-round-1",
      "logical_work_id" => "prepare-round:workflow-node-1",
      "attempt_no" => 1,
      "control_plane" => "agent",
      "payload" => {
        "request_kind" => "prepare_round",
        "task" => {
          "workflow_node_id" => "workflow-node-1",
          "conversation_id" => "conversation-1",
          "turn_id" => "turn-1",
          "kind" => "turn_step",
        },
        "round_context" => {
          "messages" => [
            { "role" => "user", "content" => "Build the 2048 acceptance path." },
          ],
          "context_imports" => [],
        },
        "agent_context" => {
          "profile" => "main",
          "allowed_tool_names" => %w[compact_context exec_command],
        },
        "provider_context" => {
          "provider_execution" => { "provider" => "openai" },
          "model_context" => { "model_slug" => "gpt-5.4" },
        },
        "runtime_context" => {
          "agent_snapshot_id" => "agent-snapshot-1",
        },
        "workspace_context" => {
          "workspace_root" => workspace_root,
        },
      },
    }
  end

  def execute_tool_mailbox_item(allowed_tool_names:, tool_name: "calculator", arguments: nil)
    {
      "item_type" => "agent_request",
      "item_id" => "mailbox-item-agent-tool-1",
      "protocol_message_id" => "protocol-message-agent-tool-1",
      "logical_work_id" => "tool-call:workflow-node-1:tool-call-1",
      "attempt_no" => 1,
      "control_plane" => "agent",
      "payload" => {
        "request_kind" => "execute_tool",
        "task" => {
          "workflow_node_id" => "workflow-node-1",
          "conversation_id" => "conversation-1",
          "turn_id" => "turn-1",
          "kind" => "turn_step",
        },
        "agent_context" => {
          "profile" => "main",
          "allowed_tool_names" => allowed_tool_names,
        },
        "provider_context" => {
          "provider_execution" => { "provider" => "openai" },
          "model_context" => { "model_slug" => "gpt-5.4" },
        },
        "runtime_context" => {
          "agent_snapshot_id" => "agent-snapshot-1",
        },
        "tool_call" => {
          "call_id" => "tool-call-1",
          "tool_name" => tool_name,
          "arguments" => arguments || {
            "expression" => "2 + 2",
          },
        },
      },
    }
  end

  def supervision_mailbox_item(request_kind:)
    {
      "item_type" => "agent_request",
      "item_id" => "mailbox-item-#{request_kind}",
      "protocol_message_id" => "protocol-message-#{request_kind}",
      "logical_work_id" => "conversation-control:control-request-1:#{request_kind}",
      "attempt_no" => 1,
      "control_plane" => "agent",
      "payload" => {
        "request_kind" => request_kind,
        "content" => (request_kind == "supervision_guidance" ? "Stop and summarize." : nil),
        "conversation_control" => {
          "conversation_control_request_id" => "control-request-1",
          "conversation_id" => "conversation-1",
          "request_kind" => request_kind == "supervision_status_refresh" ? "request_status_refresh" : "send_guidance_to_active_agent",
          "target_kind" => "conversation",
          "target_public_id" => "conversation-1",
        },
        "runtime_context" => {
          "agent_snapshot_id" => "agent-snapshot-1",
        },
      },
    }
  end

  def prepare_round_report_contract_fixture
    JSON.parse(
      File.read(
        Rails.root.join("..", "..", "shared", "fixtures", "contracts", "fenix_prepare_round_report.json")
      )
    )
  end

  def execute_tool_report_contract_fixture
    JSON.parse(
      File.read(
        Rails.root.join("..", "..", "shared", "fixtures", "contracts", "fenix_execute_tool_report.json")
      )
    )
  end

  def supervision_guidance_report_contract_fixture
    JSON.parse(
      File.read(
        Rails.root.join("..", "..", "shared", "fixtures", "contracts", "fenix_supervision_guidance_report.json")
      )
    )
  end

  def normalize_prepare_round_report(report)
    normalized = report.deep_dup
    normalized.delete("protocol_message_id")
    normalized["response_payload"] = normalized.fetch("response_payload").merge(
      "messages" => normalized.dig("response_payload", "messages").map { |message| { "role" => message.fetch("role") } },
      "trace" => normalized.dig("response_payload", "trace").map { |entry| { "hook" => entry.fetch("hook") } }
    )
    normalized
  end

  def normalize_execute_tool_report(report)
    normalized = report.deep_dup
    normalized.delete("protocol_message_id")
    normalized
  end

  def normalize_supervision_guidance_report(report)
    normalized = report.deep_dup
    normalized.delete("protocol_message_id")
    normalized
  end
end
