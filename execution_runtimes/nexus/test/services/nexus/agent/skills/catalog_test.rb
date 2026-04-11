require "test_helper"
require "tmpdir"

class Nexus::Agent::Skills::CatalogTest < ActiveSupport::TestCase
  test "loads only active skills referenced from transcript messages" do
    with_skill_fixture_roots do |roots|
      live_root = roots.fetch(:home_root).join("live")

      write_skill(root: roots.fetch(:system_root), name: "deploy-agent", description: "Deploy agents safely", body: "Use evidence-backed deploy steps.")
      write_skill(root: live_root, name: "custom-checks", description: "Custom checks", body: "Run the repo checks before delivery.")
      write_skill(root: roots.fetch(:curated_root), name: "inactive-skill", description: "Inactive", body: "This should stay inactive.")

      catalog = Nexus::Agent::Skills::Catalog.new(
        system_root: roots.fetch(:system_root),
        live_root: live_root,
        curated_root: roots.fetch(:curated_root)
      )

      selected = catalog.active_for_messages(
        messages: [
          { "role" => "user", "content" => "Use $deploy-agent and then verify." },
          { "role" => "assistant", "content" => "I will ignore $inactive-skill because it is not active." },
        ]
      )

      assert_equal ["deploy-agent"], selected.map { |entry| entry.fetch("name") }
      assert_includes selected.first.fetch("skill_md"), "Use evidence-backed deploy steps."
    end
  end

  test "reads only the live root for the selected agent and user scope" do
    with_skill_fixture_roots do |roots|
      repository_a = Nexus::Agent::Skills::Repository.new(
        agent_id: "agent-1",
        user_id: "user-1",
        home_root: roots.fetch(:home_root),
        system_root: roots.fetch(:system_root),
        curated_root: roots.fetch(:curated_root)
      )
      repository_b = Nexus::Agent::Skills::Repository.new(
        agent_id: "agent-2",
        user_id: "user-1",
        home_root: roots.fetch(:home_root),
        system_root: roots.fetch(:system_root),
        curated_root: roots.fetch(:curated_root)
      )

      write_skill(root: repository_a.live_root, name: "scope-a-checks", description: "Scope A", body: "Only scope A should see this.")
      write_skill(root: repository_b.live_root, name: "scope-b-checks", description: "Scope B", body: "Only scope B should see this.")

      catalog_a = Nexus::Agent::Skills::Catalog.new(
        system_root: roots.fetch(:system_root),
        live_root: repository_a.live_root,
        curated_root: roots.fetch(:curated_root)
      )
      catalog_b = Nexus::Agent::Skills::Catalog.new(
        system_root: roots.fetch(:system_root),
        live_root: repository_b.live_root,
        curated_root: roots.fetch(:curated_root)
      )

      selected_a = catalog_a.active_for_messages(messages: [{ "role" => "user", "content" => "Use $scope-a-checks" }])
      selected_b = catalog_b.active_for_messages(messages: [{ "role" => "user", "content" => "Use $scope-b-checks" }])

      assert_equal ["scope-a-checks"], selected_a.map { |entry| entry.fetch("name") }
      assert_equal ["scope-b-checks"], selected_b.map { |entry| entry.fetch("name") }
    end
  end

  test "requires an explicit live root" do
    with_skill_fixture_roots do |roots|
      error = assert_raises(ArgumentError) do
        Nexus::Agent::Skills::Catalog.new(
          system_root: roots.fetch(:system_root),
          curated_root: roots.fetch(:curated_root)
        )
      end

      assert_includes error.message, "live_root"
    end
  end
end
