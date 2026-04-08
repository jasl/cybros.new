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

  private

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
