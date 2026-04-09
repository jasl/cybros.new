require "test_helper"
require "tmpdir"

class Fenix::Runtime::ExecuteMailboxItemTest < ActiveSupport::TestCase
  RuntimeControlClientDouble = Struct.new(:reported_payloads, keyword_init: true) do
    def report!(payload:)
      reported_payloads << payload.deep_dup
      { "result" => "accepted" }
    end
  end

  test "prepare_round agent program requests emit a completed terminal report" do
    client = RuntimeControlClientDouble.new(reported_payloads: [])

    Dir.mktmpdir("fenix-workspace-") do |workspace_root|
      Pathname.new(workspace_root).join("AGENTS.md").write("Stay inside agents/fenix unless the task explicitly spans projects.\n")

      result = Fenix::Runtime::ExecuteMailboxItem.call(
        mailbox_item: prepare_round_mailbox_item(workspace_root: workspace_root),
        deliver_reports: true,
        control_client: client
      )

      assert_equal "ok", result.fetch("status")
      assert_equal ["agent_program_completed"], client.reported_payloads.map { |payload| payload.fetch("method_id") }
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

    result = Fenix::Runtime::ExecuteMailboxItem.call(
      mailbox_item: mailbox_item,
      deliver_reports: true,
      control_client: client
    )

    assert_equal "ok", result.fetch("status")
    assert_equal prepare_round_report_contract_fixture, normalize_prepare_round_report(client.reported_payloads.last)
  end

  test "execute_program_tool agent program requests emit a completed terminal report" do
    client = RuntimeControlClientDouble.new(reported_payloads: [])

    Dir.mktmpdir("fenix-workspace-") do |workspace_root|
      result = Fenix::Runtime::ExecuteMailboxItem.call(
        mailbox_item: execute_program_tool_mailbox_item(
          workspace_root: workspace_root,
          allowed_tool_names: %w[exec_command]
        ),
        deliver_reports: true,
        control_client: client
      )

      assert_equal "ok", result.fetch("status")
      assert_equal ["agent_program_completed"], client.reported_payloads.map { |payload| payload.fetch("method_id") }
      assert_equal "execute_program_tool", client.reported_payloads.last.fetch("request_kind")
      assert_equal "ok", client.reported_payloads.last.dig("response_payload", "status")
      assert_equal "exec_command", client.reported_payloads.last.dig("response_payload", "program_tool_call", "tool_name")
      assert_equal 0, client.reported_payloads.last.dig("response_payload", "result", "exit_status")
    end
  end

  test "execute_program_tool terminal report matches the shared contract fixture" do
    client = RuntimeControlClientDouble.new(reported_payloads: [])
    mailbox_item = JSON.parse(
      File.read(
        Rails.root.join("..", "..", "shared", "fixtures", "contracts", "core_matrix_fenix_execute_program_tool_mailbox_item.json")
      )
    )

    result = Fenix::Runtime::ExecuteMailboxItem.call(
      mailbox_item: mailbox_item,
      deliver_reports: true,
      control_client: client
    )

    assert_equal "ok", result.fetch("status")
    assert_equal execute_program_tool_report_contract_fixture, normalize_execute_program_tool_report(client.reported_payloads.last)
  end

  test "execute_program_tool failures emit a failed terminal report" do
    client = RuntimeControlClientDouble.new(reported_payloads: [])

    result = Fenix::Runtime::ExecuteMailboxItem.call(
      mailbox_item: execute_program_tool_mailbox_item(
        workspace_root: Dir.tmpdir,
        allowed_tool_names: []
      ),
      deliver_reports: true,
      control_client: client
    )

    assert_equal "failed", result.fetch("status")
    assert_equal ["agent_program_failed"], client.reported_payloads.map { |payload| payload.fetch("method_id") }
    assert_equal "execute_program_tool", client.reported_payloads.last.fetch("request_kind")
    assert_equal "tool_not_allowed", client.reported_payloads.last.dig("error_payload", "code")
  end

  test "supervision_status_refresh agent program requests emit a completed terminal report" do
    client = RuntimeControlClientDouble.new(reported_payloads: [])

    result = Fenix::Runtime::ExecuteMailboxItem.call(
      mailbox_item: supervision_mailbox_item(request_kind: "supervision_status_refresh"),
      deliver_reports: true,
      control_client: client
    )

    assert_equal "ok", result.fetch("status")
    assert_equal ["agent_program_completed"], client.reported_payloads.map { |payload| payload.fetch("method_id") }
    assert_equal "supervision_status_refresh", client.reported_payloads.last.fetch("request_kind")
    assert_equal "supervision_status_refresh", client.reported_payloads.last.dig("response_payload", "handled_request_kind")
    assert_equal "status_refresh_acknowledged", client.reported_payloads.last.dig("response_payload", "control_outcome", "outcome_kind")
  end

  test "supervision_guidance agent program requests emit a completed terminal report" do
    client = RuntimeControlClientDouble.new(reported_payloads: [])

    result = Fenix::Runtime::ExecuteMailboxItem.call(
      mailbox_item: supervision_mailbox_item(request_kind: "supervision_guidance"),
      deliver_reports: true,
      control_client: client
    )

    assert_equal "ok", result.fetch("status")
    assert_equal ["agent_program_completed"], client.reported_payloads.map { |payload| payload.fetch("method_id") }
    assert_equal "supervision_guidance", client.reported_payloads.last.fetch("request_kind")
    assert_equal "supervision_guidance", client.reported_payloads.last.dig("response_payload", "handled_request_kind")
    assert_equal "guidance_acknowledged", client.reported_payloads.last.dig("response_payload", "control_outcome", "outcome_kind")
    assert_equal "Stop and summarize.", client.reported_payloads.last.dig("response_payload", "control_outcome", "content")
  end

  test "supervision_guidance without content emits a failed terminal report" do
    client = RuntimeControlClientDouble.new(reported_payloads: [])
    mailbox_item = supervision_mailbox_item(request_kind: "supervision_guidance")
    mailbox_item.fetch("payload").delete("content")

    result = Fenix::Runtime::ExecuteMailboxItem.call(
      mailbox_item: mailbox_item,
      deliver_reports: true,
      control_client: client
    )

    assert_equal "failed", result.fetch("status")
    assert_equal ["agent_program_failed"], client.reported_payloads.map { |payload| payload.fetch("method_id") }
    assert_equal "invalid_conversation_control_request", client.reported_payloads.last.dig("error_payload", "code")
  end

  test "skills execution assignments emit started and completed terminal reports" do
    client = RuntimeControlClientDouble.new(reported_payloads: [])
    original_load = Fenix::Skills::Load.method(:call)
    Fenix::Skills::Load.define_singleton_method(:call) do |skill_name:, repository:|
      {
        "name" => skill_name,
        "scope" => [
          repository.scope_roots.agent_program_id,
          repository.scope_roots.user_id,
        ],
      }
    end

    result = Fenix::Runtime::ExecuteMailboxItem.call(
      mailbox_item: execution_assignment_mailbox_item(
        mode: "skills_load",
        task_payload: { "skill_name" => "portable-notes" },
        runtime_context: {
          "agent_program_id" => "agent-program-1",
          "user_id" => "user-1",
          "agent_program_version_id" => "agent-program-version-1",
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
    Fenix::Skills::Load.define_singleton_method(:call, original_load) if original_load
  end

  test "deterministic tool execution assignments emit started and completed terminal reports" do
    client = RuntimeControlClientDouble.new(reported_payloads: [])

    result = Fenix::Runtime::ExecuteMailboxItem.call(
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

  test "skills execution assignments emit started before deterministic scope failures" do
    client = RuntimeControlClientDouble.new(reported_payloads: [])

    result = Fenix::Runtime::ExecuteMailboxItem.call(
      mailbox_item: execution_assignment_mailbox_item(
        mode: "skills_catalog_list",
        runtime_context: {
          "agent_program_version_id" => "agent-program-version-1",
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

    result = Fenix::Runtime::ExecuteMailboxItem.call(
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
    original_call = Fenix::Runtime::Assignments::DispatchMode.method(:call)

    Fenix::Runtime::Assignments::DispatchMode.define_singleton_method(:call) do |**|
      { "kind" => "unsupported_kind" }
    end

    result = Fenix::Runtime::ExecuteMailboxItem.call(
      mailbox_item: execution_assignment_mailbox_item(mode: "deterministic_tool"),
      deliver_reports: true,
      control_client: client
    )

    assert_equal "failed", result.fetch("status")
    assert_equal ["execution_started", "execution_fail"], client.reported_payloads.map { |payload| payload.fetch("method_id") }
    assert_equal "unsupported_execution_assignment_dispatch_kind", client.reported_payloads.last.dig("terminal_payload", "code")
    assert_match(/unsupported execution assignment dispatch kind/i, client.reported_payloads.last.dig("terminal_payload", "message"))
  ensure
    Fenix::Runtime::Assignments::DispatchMode.define_singleton_method(:call, original_call) if original_call
  end

  private

  def execution_assignment_mailbox_item(mode:, task_payload: {}, runtime_context: {})
    {
      "item_type" => "execution_assignment",
      "item_id" => "mailbox-item-execution-assignment-1",
      "protocol_message_id" => "protocol-message-execution-assignment-1",
      "logical_work_id" => "logical-work-execution-assignment-1",
      "attempt_no" => 1,
      "control_plane" => "program",
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
      "item_type" => "agent_program_request",
      "item_id" => "mailbox-item-prepare-round-1",
      "protocol_message_id" => "protocol-message-prepare-round-1",
      "logical_work_id" => "prepare-round:workflow-node-1",
      "attempt_no" => 1,
      "control_plane" => "program",
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
          "agent_program_version_id" => "agent-program-version-1",
        },
        "workspace_context" => {
          "workspace_root" => workspace_root,
        },
      },
    }
  end

  def execute_program_tool_mailbox_item(workspace_root:, allowed_tool_names:)
    {
      "item_type" => "agent_program_request",
      "item_id" => "mailbox-item-program-tool-1",
      "protocol_message_id" => "protocol-message-program-tool-1",
      "logical_work_id" => "program-tool:workflow-node-1:tool-call-1",
      "attempt_no" => 1,
      "control_plane" => "program",
      "payload" => {
        "request_kind" => "execute_program_tool",
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
          "agent_program_version_id" => "agent-program-version-1",
        },
        "workspace_context" => {
          "workspace_root" => workspace_root,
        },
        "program_tool_call" => {
          "call_id" => "tool-call-1",
          "tool_name" => "exec_command",
          "arguments" => {
            "command_line" => "printf 'hello\\n'",
          },
        },
      },
    }
  end

  def supervision_mailbox_item(request_kind:)
    {
      "item_type" => "agent_program_request",
      "item_id" => "mailbox-item-#{request_kind}",
      "protocol_message_id" => "protocol-message-#{request_kind}",
      "logical_work_id" => "conversation-control:control-request-1:#{request_kind}",
      "attempt_no" => 1,
      "control_plane" => "program",
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
          "agent_program_version_id" => "agent-program-version-1",
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

  def execute_program_tool_report_contract_fixture
    JSON.parse(
      File.read(
        Rails.root.join("..", "..", "shared", "fixtures", "contracts", "fenix_execute_program_tool_report.json")
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

  def normalize_execute_program_tool_report(report)
    normalized = report.deep_dup
    normalized.delete("protocol_message_id")
    normalized
  end
end
