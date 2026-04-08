require "test_helper"

class Fenix::Skills::ReadFileTest < ActiveSupport::TestCase
  test "reads a file relative to the skill root" do
    with_skill_roots do |roots|
      write_skill(
        root: roots.fetch(:live_root),
        name: "portable-notes",
        description: "Capture notes.",
        extra_files: { "references/checklist.md" => "# Checklist\n" }
      )

      repository = Fenix::Skills::Repository.new(**roots)
      payload = Fenix::Skills::ReadFile.call(
        skill_name: "portable-notes",
        relative_path: "references/checklist.md",
        repository: repository
      )

      assert_equal "references/checklist.md", payload.fetch("relative_path")
      assert_equal "# Checklist\n", payload.fetch("content")
    end
  end

  test "rejects path traversal outside the skill root" do
    with_skill_roots do |roots|
      write_skill(root: roots.fetch(:live_root), name: "portable-notes", description: "Capture notes.")
      repository = Fenix::Skills::Repository.new(**roots)

      assert_raises(Fenix::Skills::Repository::InvalidFileReference) do
        Fenix::Skills::ReadFile.call(
          skill_name: "portable-notes",
          relative_path: "../secrets.txt",
          repository: repository
        )
      end
    end
  end
end
