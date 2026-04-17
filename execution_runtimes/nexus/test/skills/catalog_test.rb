require "test_helper"

class SkillsCatalogTest < Minitest::Test
  def test_discovers_only_active_skills_requested_by_messages
    repository = build_repository(agent_id: "agent-1", user_id: "user-1")
    write_skill(root: repository.system_root, name: "deploy-agent", description: "Deploy safely", body: "Use evidence-backed deploy steps.")
    write_skill(root: repository.live_root, name: "custom-checks", description: "Custom checks", body: "Run checks.")
    write_skill(root: repository.curated_root, name: "inactive-skill", description: "Inactive", body: "Inactive skill.")

    catalog = CybrosNexus::Skills::Catalog.new(repository: repository)
    selected = catalog.active_for_messages(
      messages: [
        { "role" => "user", "content" => "Use $deploy-agent before shipping." },
        { "role" => "assistant", "content" => "Do not load $inactive-skill." },
      ]
    )

    assert_equal ["deploy-agent"], selected.map { |entry| entry.fetch("name") }
    assert_includes selected.first.fetch("skill_md"), "Use evidence-backed deploy steps."
  end

  private

  def build_repository(agent_id:, user_id:)
    CybrosNexus::Skills::Repository.new(
      agent_id: agent_id,
      user_id: user_id,
      skills_root: tmp_path("nexus-home/skills")
    )
  end

  def write_skill(root:, name:, description:, body:, dir_name: name)
    skill_root = File.join(root, dir_name)
    FileUtils.mkdir_p(skill_root)
    File.write(
      File.join(skill_root, "SKILL.md"),
      <<~MARKDOWN
        ---
        name: #{name}
        description: #{description}
        ---

        #{body}
      MARKDOWN
    )
    skill_root
  end
end
