require "test_helper"

class Nexus::Agent::Skills::PackageValidatorTest < ActiveSupport::TestCase
  test "accepts a valid skill package and returns normalized metadata" do
    with_skill_fixture_roots do |roots|
      skill_root = write_skill(
        root: roots.fetch(:home_root),
        name: "portable-notes",
        description: "Capture notes.",
        body: "Capture notes safely."
      )

      metadata = Nexus::Agent::Skills::PackageValidator.call(skill_root: skill_root)

      assert_equal(
        {
          "name" => "portable-notes",
          "description" => "Capture notes.",
        },
        metadata
      )
    end
  end

  test "rejects a package when the frontmatter name does not match the directory name" do
    with_skill_fixture_roots do |roots|
      skill_root = write_skill(
        root: roots.fetch(:home_root),
        dir_name: "portable-notes",
        name: "portable-checklists",
        description: "Capture notes."
      )

      error = assert_raises(Nexus::Agent::Skills::PackageValidator::InvalidSkillPackage) do
        Nexus::Agent::Skills::PackageValidator.call(skill_root: skill_root)
      end

      assert_includes error.message, "directory"
    end
  end

  test "rejects a package when the skill name violates the accepted agent skills format" do
    with_skill_fixture_roots do |roots|
      skill_root = write_skill(
        root: roots.fetch(:home_root),
        name: "Portable-Notes",
        description: "Capture notes.",
        dir_name: "Portable-Notes"
      )

      error = assert_raises(Nexus::Agent::Skills::PackageValidator::InvalidSkillPackage) do
        Nexus::Agent::Skills::PackageValidator.call(skill_root: skill_root)
      end

      assert_includes error.message, "name"
    end
  end

  test "rejects a package when the description exceeds the accepted limit" do
    with_skill_fixture_roots do |roots|
      skill_root = write_skill(
        root: roots.fetch(:home_root),
        name: "portable-notes",
        description: "x" * 1025
      )

      error = assert_raises(Nexus::Agent::Skills::PackageValidator::InvalidSkillPackage) do
        Nexus::Agent::Skills::PackageValidator.call(skill_root: skill_root)
      end

      assert_includes error.message, "description"
    end
  end

  test "rejects a package when required metadata is missing" do
    with_skill_fixture_roots do |roots|
      skill_root = roots.fetch(:home_root).join("portable-notes")
      FileUtils.mkdir_p(skill_root)
      skill_root.join("SKILL.md").write(
        <<~MARKDOWN
          ---
          name: portable-notes
          ---

          Capture notes safely.
        MARKDOWN
      )

      error = assert_raises(Nexus::Agent::Skills::PackageValidator::InvalidSkillPackage) do
        Nexus::Agent::Skills::PackageValidator.call(skill_root: skill_root)
      end

      assert_includes error.message, "description"
    end
  end

  test "rejects a package that contains symlinks" do
    with_skill_fixture_roots do |roots|
      skill_root = write_skill(
        root: roots.fetch(:home_root),
        name: "portable-notes",
        description: "Capture notes."
      )
      outside_file = roots.fetch(:home_root).join("outside.txt")
      outside_file.write("outside scope\n")
      File.symlink(outside_file, skill_root.join("docs-link.md"))

      error = assert_raises(Nexus::Agent::Skills::PackageValidator::InvalidSkillPackage) do
        Nexus::Agent::Skills::PackageValidator.call(skill_root: skill_root)
      end

      assert_includes error.message, "symlink"
    end
  end
end
