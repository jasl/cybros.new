require "test_helper"

class Fenix::Skills::LoadTest < ActiveSupport::TestCase
  test "loads an active live skill with its files" do
    with_skill_roots do |roots|
      write_skill(
        root: roots.fetch(:live_root),
        name: "portable-notes",
        description: "Capture notes.",
        extra_files: { "scripts/format_notes.rb" => "puts 'ok'\n" }
      )

      repository = Fenix::Skills::Repository.new(**roots)
      loaded = Fenix::Skills::Load.call(skill_name: "portable-notes", repository: repository)

      assert_equal "portable-notes", loaded.fetch("name")
      assert_equal "live", loaded.fetch("source_kind")
      assert_includes loaded.fetch("files"), "scripts/format_notes.rb"
      assert_match(/Capture notes/, loaded.fetch("skill_md"))
    end
  end

  test "does not treat curated-only skills as active" do
    with_skill_roots do |roots|
      write_skill(root: roots.fetch(:curated_root), name: "research-brief", description: "Write a brief.")

      repository = Fenix::Skills::Repository.new(**roots)

      assert_raises(Fenix::Skills::Repository::SkillNotFound) do
        Fenix::Skills::Load.call(skill_name: "research-brief", repository: repository)
      end
    end
  end
end
