require "test_helper"

class Fenix::Skills::CatalogListTest < ActiveSupport::TestCase
  test "lists system, live, and curated skills with active state" do
    with_skill_roots do |roots|
      write_skill(root: roots.fetch(:system_root), name: "deploy-agent", description: "Deploy another agent.")
      write_skill(root: roots.fetch(:curated_root), name: "research-brief", description: "Write a brief.")
      write_skill(root: roots.fetch(:live_root), name: "portable-notes", description: "Capture notes.")

      repository = Fenix::Skills::Repository.new(**roots)
      catalog = Fenix::Skills::CatalogList.call(repository: repository)

      assert_equal [
        ["deploy-agent", "system", true],
        ["portable-notes", "live", true],
        ["research-brief", "curated", false],
      ], catalog.map { |entry| [entry.fetch("name"), entry.fetch("source_kind"), entry.fetch("active")] }
    end
  end
end
