require "test_helper"

class Nexus::Agent::Skills::CatalogListTest < ActiveSupport::TestCase
  test "delegates catalog listing through the repository" do
    repository = Struct.new(:catalog_output) do
      def catalog_list
        catalog_output
      end
    end.new([{ "name" => "portable-notes" }])

    assert_equal [{ "name" => "portable-notes" }], Nexus::Agent::Skills::CatalogList.call(repository: repository)
  end
end
