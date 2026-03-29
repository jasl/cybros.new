require "test_helper"

class SkillsFlowTest < ActionDispatch::IntegrationTest
  test "runtime execution lists bundled system and curated skills" do
    with_skill_roots do |roots|
      write_skill(root: roots.fetch(:system_root), name: "deploy-agent", description: "Deploy another agent.")
      write_skill(root: roots.fetch(:curated_root), name: "research-brief", description: "Write a brief.")

      post "/runtime/executions",
        params: runtime_assignment_payload(mode: "skills_catalog_list"),
        as: :json

      assert_response :success

      body = JSON.parse(response.body)

      assert_equal "completed", body.fetch("status")
      assert_equal [
        ["deploy-agent", "system", true],
        ["research-brief", "curated", false],
      ], body.fetch("output").map { |entry| [entry.fetch("name"), entry.fetch("source_kind"), entry.fetch("active")] }
    end
  end

  test "runtime execution loads the built-in deploy-agent skill" do
    with_skill_roots do |roots|
      write_skill(
        root: roots.fetch(:system_root),
        name: "deploy-agent",
        description: "Deploy another agent.",
        extra_files: { "scripts/deploy_agent.rb" => "puts 'deploy'\n" }
      )

      post "/runtime/executions",
        params: runtime_assignment_payload(
          mode: "skills_load",
          task_payload: { "skill_name" => "deploy-agent" }
        ),
        as: :json

      assert_response :success

      body = JSON.parse(response.body)

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

      post "/runtime/executions",
        params: runtime_assignment_payload(
          mode: "skills_install",
          task_payload: { "source_path" => File.join(source_root, "portable-notes") }
        ),
        as: :json

      assert_response :success
      install_body = JSON.parse(response.body)

      assert_equal "completed", install_body.fetch("status")
      assert_equal "next_top_level_turn", install_body.dig("output", "activation_state")

      post "/runtime/executions",
        params: runtime_assignment_payload(
          mode: "skills_load",
          task_payload: { "skill_name" => "portable-notes" }
        ),
        as: :json

      assert_response :success
      load_body = JSON.parse(response.body)

      assert_equal "portable-notes", load_body.dig("output", "name")

      post "/runtime/executions",
        params: runtime_assignment_payload(
          mode: "skills_read_file",
          task_payload: {
            "skill_name" => "portable-notes",
            "relative_path" => "references/checklist.md",
          }
        ),
        as: :json

      assert_response :success
      read_body = JSON.parse(response.body)

      assert_equal "# Checklist\n", read_body.dig("output", "content")
    end
  end
end
