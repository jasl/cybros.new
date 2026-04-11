require "test_helper"

class Nexus::Agent::Skills::ReadFileTest < ActiveSupport::TestCase
  test "delegates file reads through the repository" do
    repository = Struct.new(:captured_args) do
      def read_file(skill_name:, relative_path:)
        self.captured_args = {
          "skill_name" => skill_name,
          "relative_path" => relative_path,
        }
        { "content" => "# Checklist\n" }
      end
    end.new

    result = Nexus::Agent::Skills::ReadFile.call(
      skill_name: "portable-notes",
      relative_path: "references/checklist.md",
      repository: repository
    )

    assert_equal(
      {
        "skill_name" => "portable-notes",
        "relative_path" => "references/checklist.md",
      },
      repository.captured_args
    )
    assert_equal "# Checklist\n", result.fetch("content")
  end
end
