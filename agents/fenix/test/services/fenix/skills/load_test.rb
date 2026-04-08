require "test_helper"

class Fenix::Skills::LoadTest < ActiveSupport::TestCase
  test "delegates load through the repository" do
    repository = Struct.new(:loaded_skill_name) do
      def load(skill_name:)
        self.loaded_skill_name = skill_name
        { "name" => skill_name }
      end
    end.new

    result = Fenix::Skills::Load.call(skill_name: "portable-notes", repository: repository)

    assert_equal "portable-notes", repository.loaded_skill_name
    assert_equal "portable-notes", result.fetch("name")
  end
end
