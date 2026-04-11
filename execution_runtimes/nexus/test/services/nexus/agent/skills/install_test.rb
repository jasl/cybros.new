require "test_helper"

class Nexus::Agent::Skills::InstallTest < ActiveSupport::TestCase
  test "delegates installs through the repository" do
    repository = Struct.new(:installed_source_path) do
      def install(source_path:)
        self.installed_source_path = source_path
        { "name" => "portable-notes" }
      end
    end.new

    result = Nexus::Agent::Skills::Install.call(
      source_path: "/tmp/portable-notes",
      repository: repository
    )

    assert_equal "/tmp/portable-notes", repository.installed_source_path
    assert_equal "portable-notes", result.fetch("name")
  end
end
