require "test_helper"

class SkillsFlowTest < ActiveSupport::TestCase
  test "mailbox worker lists bundled system and curated skills" do
    with_skill_roots do |roots|
      write_skill(root: roots.fetch(:system_root), name: "deploy-agent", description: "Deploy another agent.")
      write_skill(root: roots.fetch(:curated_root), name: "research-brief", description: "Write a brief.")

      body = run_runtime_execution(runtime_assignment_payload(mode: "skills_catalog_list"))

      assert_equal "completed", body.fetch("status")
      assert_equal [
        ["deploy-agent", "system", true],
        ["research-brief", "curated", false],
      ], body.fetch("output").map { |entry| [entry.fetch("name"), entry.fetch("source_kind"), entry.fetch("active")] }
    end
  end

  test "mailbox worker loads the built-in deploy-agent skill" do
    with_skill_roots do |roots|
      write_skill(
        root: roots.fetch(:system_root),
        name: "deploy-agent",
        description: "Deploy another agent.",
        extra_files: { "scripts/deploy_agent.rb" => "puts 'deploy'\n" }
      )

      body = run_runtime_execution(
        runtime_assignment_payload(
          mode: "skills_load",
          task_payload: { "skill_name" => "deploy-agent" }
        )
      )

      assert_equal "completed", body.fetch("status")
      assert_equal "deploy-agent", body.dig("output", "name")
      assert_includes body.dig("output", "files"), "scripts/deploy_agent.rb"
    end
  end

  test "installed third-party skills become available on the next top-level turn" do
    with_skill_roots do |roots|
      write_skill(root: roots.fetch(:system_root), name: "deploy-agent", description: "Deploy another agent.")
      source_root = Dir.mktmpdir("fenix-third-party-skill-")
      write_skill(
        root: source_root,
        name: "portable-notes",
        description: "Capture notes.",
        extra_files: { "references/checklist.md" => "# Checklist\n" }
      )

      install_body = run_runtime_execution(
        runtime_assignment_payload(
          mode: "skills_install",
          task_payload: { "source_path" => File.join(source_root, "portable-notes") }
        )
      )

      assert_equal "completed", install_body.fetch("status")
      assert_equal "next_top_level_turn", install_body.dig("output", "activation_state")

      load_body = run_runtime_execution(
        runtime_assignment_payload(
          mode: "skills_load",
          task_payload: { "skill_name" => "portable-notes" }
        )
      )

      assert_equal "portable-notes", load_body.dig("output", "name")

      read_body = run_runtime_execution(
        runtime_assignment_payload(
          mode: "skills_read_file",
          task_payload: {
            "skill_name" => "portable-notes",
            "relative_path" => "references/checklist.md",
          }
        )
      )

      assert_equal "# Checklist\n", read_body.dig("output", "content")
    end
  end

  private

  def run_runtime_execution(payload)
    runtime_execution = nil

    assert_enqueued_jobs 1 do
      runtime_execution = Fenix::Runtime::MailboxWorker.call(mailbox_item: payload)
      assert_equal "queued", runtime_execution.status
    end

    perform_enqueued_jobs

    serialize_runtime_execution(runtime_execution.reload)
  end

  def serialize_runtime_execution(runtime_execution)
    {
      "execution_id" => runtime_execution.execution_id,
      "status" => runtime_execution.status,
      "output" => runtime_execution.output_payload,
      "error" => runtime_execution.error_payload,
      "reports" => runtime_execution.reports,
      "trace" => runtime_execution.trace,
      "mailbox_item_id" => runtime_execution.mailbox_item_id,
      "logical_work_id" => runtime_execution.logical_work_id,
      "attempt_no" => runtime_execution.attempt_no,
      "runtime_plane" => runtime_execution.runtime_plane,
      "started_at" => runtime_execution.started_at,
      "finished_at" => runtime_execution.finished_at,
    }.compact
  end
end
