require "test_helper"

class Skills::RepositoryTest < ActiveSupport::TestCase
  test "scopes writable roots under the nexus home root by agent and user" do
    with_skill_fixture_roots do |roots|
      repository = Skills::Repository.new(
        agent_id: "agent-1",
        user_id: "user-1",
        home_root: roots.fetch(:home_root),
        system_root: roots.fetch(:system_root),
        curated_root: roots.fetch(:curated_root)
      )

      assert_equal roots.fetch(:home_root).join("skills-scopes", "agent-1", "user-1", "live"), repository.live_root
      assert_equal roots.fetch(:home_root).join("skills-scopes", "agent-1", "user-1", "staging"), repository.staging_root
      assert_equal roots.fetch(:home_root).join("skills-scopes", "agent-1", "user-1", "backups"), repository.backup_root
    end
  end

  test "installs a third-party skill through staging and writes provenance in the current scope" do
    with_skill_fixture_roots do |roots|
      source_root = Dir.mktmpdir("nexus-third-party-skill-")
      write_skill(
        root: source_root,
        name: "portable-notes",
        description: "Capture notes.",
        body: "Capture notes safely.",
        extra_files: { "scripts/format_notes.rb" => "puts 'ok'\n" }
      )

      repository = Skills::Repository.new(
        agent_id: "agent-1",
        user_id: "user-1",
        home_root: roots.fetch(:home_root),
        system_root: roots.fetch(:system_root),
        curated_root: roots.fetch(:curated_root)
      )
      result = repository.install(source_path: File.join(source_root, "portable-notes"))

      assert_equal "portable-notes", result.fetch("name")
      assert_equal "next_top_level_turn", result.fetch("activation_state")
      assert_equal repository.live_root.join("portable-notes").to_s, result.fetch("live_root")
      assert File.exist?(File.join(result.fetch("live_root"), "SKILL.md"))

      provenance = JSON.parse(File.read(result.fetch("provenance_path")))
      assert_equal File.join(source_root, "portable-notes"), provenance.fetch("source_path")
    end
  end

  test "shares installed skills across repositories in the same scope and isolates a different agent scope" do
    with_skill_fixture_roots do |roots|
      source_root = Dir.mktmpdir("nexus-third-party-skill-")
      write_skill(root: source_root, name: "portable-notes", description: "Capture notes.", body: "Capture notes safely.")

      repository_a1 = Skills::Repository.new(
        agent_id: "agent-1",
        user_id: "user-1",
        home_root: roots.fetch(:home_root),
        system_root: roots.fetch(:system_root),
        curated_root: roots.fetch(:curated_root)
      )
      repository_a2 = Skills::Repository.new(
        agent_id: "agent-1",
        user_id: "user-1",
        home_root: roots.fetch(:home_root),
        system_root: roots.fetch(:system_root),
        curated_root: roots.fetch(:curated_root)
      )
      repository_b = Skills::Repository.new(
        agent_id: "agent-2",
        user_id: "user-1",
        home_root: roots.fetch(:home_root),
        system_root: roots.fetch(:system_root),
        curated_root: roots.fetch(:curated_root)
      )

      repository_a1.install(source_path: File.join(source_root, "portable-notes"))

      assert_equal "portable-notes", repository_a2.load(skill_name: "portable-notes").fetch("name")

      assert_raises(Skills::Repository::SkillNotFound) do
        repository_b.load(skill_name: "portable-notes")
      end
    end
  end

  test "rejects installs that collide with reserved system skill names" do
    with_skill_fixture_roots do |roots|
      write_skill(root: roots.fetch(:system_root), name: "deploy-agent", description: "Deploy another agent.")
      source_root = Dir.mktmpdir("nexus-third-party-skill-")
      write_skill(root: source_root, name: "deploy-agent", description: "Override the system skill.")

      repository = Skills::Repository.new(
        agent_id: "agent-1",
        user_id: "user-1",
        home_root: roots.fetch(:home_root),
        system_root: roots.fetch(:system_root),
        curated_root: roots.fetch(:curated_root)
      )

      assert_raises(Skills::Repository::ReservedSkillNameError) do
        repository.install(source_path: File.join(source_root, "deploy-agent"))
      end
    end
  end

  test "requires non-blank and path-safe agent and user scope ids" do
    with_skill_fixture_roots do |roots|
      error = assert_raises(ArgumentError) do
        Skills::Repository.new(
          agent_id: "",
          user_id: "user-1",
          home_root: roots.fetch(:home_root),
          system_root: roots.fetch(:system_root),
          curated_root: roots.fetch(:curated_root)
        )
      end

      assert_includes error.message, "agent_id"

      error = assert_raises(ArgumentError) do
        Skills::Repository.new(
          agent_id: "agent-1",
          user_id: "",
          home_root: roots.fetch(:home_root),
          system_root: roots.fetch(:system_root),
          curated_root: roots.fetch(:curated_root)
        )
      end

      assert_includes error.message, "user_id"

      error = assert_raises(ArgumentError) do
        Skills::Repository.new(
          agent_id: "..",
          user_id: "user-1",
          home_root: roots.fetch(:home_root),
          system_root: roots.fetch(:system_root),
          curated_root: roots.fetch(:curated_root)
        )
      end

      assert_includes error.message, "agent_id"

      error = assert_raises(ArgumentError) do
        Skills::Repository.new(
          agent_id: "agent-1",
          user_id: "..",
          home_root: roots.fetch(:home_root),
          system_root: roots.fetch(:system_root),
          curated_root: roots.fetch(:curated_root)
        )
      end

      assert_includes error.message, "user_id"
    end
  end

  test "read_file rejects symlink targets even when metadata validation is bypassed" do
    with_skill_fixture_roots do |roots|
      outside_file = roots.fetch(:home_root).join("outside.txt")
      outside_file.write("outside scope\n")

      skill_root = write_skill(
        root: roots.fetch(:home_root).join("skills-scopes", "agent-1", "user-1", "live"),
        name: "portable-notes",
        description: "Capture notes."
      )
      File.symlink(outside_file, skill_root.join("docs-link.md"))

      validator = Class.new do
        def self.call(skill_root:)
          {
            "name" => skill_root.basename.to_s,
            "description" => "Bypassed for read_file test.",
          }
        end
      end

      repository = Skills::Repository.new(
        agent_id: "agent-1",
        user_id: "user-1",
        home_root: roots.fetch(:home_root),
        system_root: roots.fetch(:system_root),
        curated_root: roots.fetch(:curated_root),
        validator: validator
      )

      assert_raises(Skills::Repository::InvalidFileReference) do
        repository.read_file(skill_name: "portable-notes", relative_path: "docs-link.md")
      end
    end
  end
end
