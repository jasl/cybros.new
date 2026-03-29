require "test_helper"

class Fenix::Skills::InstallTest < ActiveSupport::TestCase
  test "installs a third-party skill through staging and writes provenance" do
    with_skill_roots do |roots|
      source_root = Dir.mktmpdir("fenix-third-party-skill-")
      write_skill(
        root: source_root,
        name: "portable-notes",
        description: "Capture notes.",
        extra_files: { "scripts/format_notes.rb" => "puts 'ok'\n" }
      )

      repository = Fenix::Skills::Repository.new(**roots)
      result = Fenix::Skills::Install.call(
        source_path: File.join(source_root, "portable-notes"),
        repository: repository
      )

      assert_equal "portable-notes", result.fetch("name")
      assert_equal "next_top_level_turn", result.fetch("activation_state")
      assert File.exist?(File.join(result.fetch("live_root"), "SKILL.md"))

      provenance = JSON.parse(File.read(result.fetch("provenance_path")))
      assert_equal File.join(source_root, "portable-notes"), provenance.fetch("source_path")
    end
  end

  test "snapshots the old live skill before replacement" do
    with_skill_roots do |roots|
      live_skill = write_skill(root: roots.fetch(:live_root), name: "portable-notes", description: "Old description.")
      source_root = Dir.mktmpdir("fenix-third-party-skill-")
      write_skill(root: source_root, name: "portable-notes", description: "New description.")

      repository = Fenix::Skills::Repository.new(**roots)
      result = Fenix::Skills::Install.call(
        source_path: File.join(source_root, "portable-notes"),
        repository: repository
      )

      assert File.directory?(result.fetch("backup_root"))
      assert_match(/Old description/, File.read(File.join(result.fetch("backup_root"), "SKILL.md")))
      assert_match(/New description/, File.read(live_skill.join("SKILL.md")))
    end
  end

  test "rejects installs that collide with reserved system skill names" do
    with_skill_roots do |roots|
      write_skill(root: roots.fetch(:system_root), name: "deploy-agent", description: "Deploy another agent.")
      source_root = Dir.mktmpdir("fenix-third-party-skill-")
      write_skill(root: source_root, name: "deploy-agent", description: "Override the system skill.")

      repository = Fenix::Skills::Repository.new(**roots)

      assert_raises(Fenix::Skills::Repository::ReservedSkillNameError) do
        Fenix::Skills::Install.call(
          source_path: File.join(source_root, "deploy-agent"),
          repository: repository
        )
      end
    end
  end
end
