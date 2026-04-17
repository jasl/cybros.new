require "test_helper"

class SkillsInstallTest < Minitest::Test
  def test_install_is_idempotent_for_the_same_skill_source
    repository = CybrosNexus::Skills::Repository.new(
      agent_id: "agent-1",
      user_id: "user-1",
      skills_root: tmp_path("nexus-home/skills")
    )
    source_root = tmp_path("source-skills")
    write_skill(root: source_root, name: "portable-notes", description: "Capture notes.", body: "Capture notes safely.")

    first = CybrosNexus::Skills::Install.call(
      source_path: File.join(source_root, "portable-notes"),
      repository: repository
    )
    second = CybrosNexus::Skills::Install.call(
      source_path: File.join(source_root, "portable-notes"),
      repository: repository
    )

    assert_equal "portable-notes", first.fetch("name")
    assert_equal first.fetch("live_root"), second.fetch("live_root")
    assert_equal ["portable-notes"], repository.catalog_list.select { |entry| entry.fetch("active") }.map { |entry| entry.fetch("name") }
  end

  def test_install_rejects_invalid_skill_packages
    repository = CybrosNexus::Skills::Repository.new(
      agent_id: "agent-1",
      user_id: "user-1",
      skills_root: tmp_path("nexus-home/skills")
    )
    source_root = tmp_path("source-skills")
    invalid_root = File.join(source_root, "Portable-Notes")
    FileUtils.mkdir_p(invalid_root)
    File.write(
      File.join(invalid_root, "SKILL.md"),
      <<~MARKDOWN
        ---
        name: Portable-Notes
        description: Invalid casing.
        ---

        Invalid package.
      MARKDOWN
    )

    error = assert_raises(CybrosNexus::Skills::Repository::InvalidSkillPackage) do
      CybrosNexus::Skills::Install.call(
        source_path: invalid_root,
        repository: repository
      )
    end

    assert_includes error.message, "lowercase"
  end

  private

  def write_skill(root:, name:, description:, body:)
    skill_root = File.join(root, name)
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
