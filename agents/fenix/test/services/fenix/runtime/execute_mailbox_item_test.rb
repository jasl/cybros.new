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
end
