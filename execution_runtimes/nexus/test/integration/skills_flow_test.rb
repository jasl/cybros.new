require "test_helper"
require "tmpdir"

class SkillsFlowTest < ActiveSupport::TestCase
  test "mailbox worker installs a skill in one scope and loads and reads it in the next top-level turn" do
    with_skill_fixture_roots do |roots|
      source_root = Dir.mktmpdir("nexus-third-party-skill-")
      write_skill(
        root: source_root,
        name: "portable-notes",
        description: "Capture notes.",
        extra_files: { "references/checklist.md" => "# Checklist\n" }
      )

      previous_home_root = ENV["NEXUS_HOME_ROOT"]
      ENV["NEXUS_HOME_ROOT"] = roots.fetch(:home_root).to_s

      install_result = Nexus::Runtime::MailboxWorker.call(
        mailbox_item: runtime_assignment_mailbox_item(
          mode: "skills_install",
          conversation_id: "conversation-a",
          task_payload: { "source_path" => File.join(source_root, "portable-notes") }
        ),
        inline: true
      )

      assert_equal "ok", install_result.fetch("status")
      assert_equal "next_top_level_turn", install_result.dig("output", "activation_state")

      load_result = Nexus::Runtime::MailboxWorker.call(
        mailbox_item: runtime_assignment_mailbox_item(
          mode: "skills_load",
          conversation_id: "conversation-b",
          task_payload: { "skill_name" => "portable-notes" }
        ),
        inline: true
      )

      assert_equal "ok", load_result.fetch("status")
      assert_equal "portable-notes", load_result.dig("output", "name")

      read_result = Nexus::Runtime::MailboxWorker.call(
        mailbox_item: runtime_assignment_mailbox_item(
          mode: "skills_read_file",
          conversation_id: "conversation-b",
          task_payload: {
            "skill_name" => "portable-notes",
            "relative_path" => "references/checklist.md",
          }
        ),
        inline: true
      )

      assert_equal "ok", read_result.fetch("status")
      assert_equal "# Checklist\n", read_result.dig("output", "content")
    ensure
      ENV["NEXUS_HOME_ROOT"] = previous_home_root
    end
  end

  private

  def runtime_assignment_mailbox_item(mode:, conversation_id:, task_payload:)
    {
      "item_type" => "execution_assignment",
      "item_id" => "mailbox-item-#{mode}-#{conversation_id}",
      "protocol_message_id" => "protocol-message-#{mode}-#{conversation_id}",
      "logical_work_id" => "logical-work-#{mode}-#{conversation_id}",
      "attempt_no" => 1,
      "control_plane" => "execution_runtime",
      "payload" => {
        "request_kind" => "execution_assignment",
        "task" => {
          "agent_task_run_id" => "agent-task-run-#{conversation_id}",
          "workflow_run_id" => "workflow-run-#{conversation_id}",
          "workflow_node_id" => "workflow-node-#{conversation_id}",
          "conversation_id" => conversation_id,
          "turn_id" => "turn-#{conversation_id}",
          "kind" => "turn_step",
        },
        "runtime_context" => {
          "agent_id" => "agent-1",
          "user_id" => "user-1",
          "agent_version_id" => "agent-snapshot-1",
        },
        "task_payload" => {
          "mode" => mode,
        }.merge(task_payload),
      },
    }
  end
end
