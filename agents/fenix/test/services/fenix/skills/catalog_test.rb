require "test_helper"
require "tmpdir"

class Fenix::Skills::CatalogTest < ActiveSupport::TestCase
  test "loads only active skills referenced from transcript messages" do
    Dir.mktmpdir("fenix-skills-") do |skills_root|
      system_root = Pathname.new(skills_root).join(".system")
      live_root = Pathname.new(skills_root).join("live")
      curated_root = Pathname.new(skills_root).join(".curated")

      write_skill(system_root, "deploy-agent", "Deploy agents safely", "Use evidence-backed deploy steps.")
      write_skill(live_root, "custom-checks", "Custom checks", "Run the repo checks before delivery.")
      write_skill(curated_root, "inactive-skill", "Inactive", "This should stay inactive.")

      catalog = Fenix::Skills::Catalog.new(
        system_root: system_root,
        live_root: live_root,
        curated_root: curated_root
      )

      selected = catalog.active_for_messages(
        messages: [
          { "role" => "user", "content" => "Use $deploy-agent and then verify." },
          { "role" => "assistant", "content" => "I will ignore $inactive-skill because it is not active." },
        ]
      )

      assert_equal ["deploy-agent"], selected.map { |entry| entry.fetch("name") }
      assert_includes selected.first.fetch("skill_md"), "Use evidence-backed deploy steps."
    end
  end

  private

  def write_skill(root, name, description, body)
    skill_root = root.join(name)
    FileUtils.mkdir_p(skill_root)
    skill_root.join("SKILL.md").write(
      <<~MARKDOWN
        ---
        name: #{name}
        description: #{description}
        ---

        #{body}
      MARKDOWN
    )
  end
end
