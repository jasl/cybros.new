require "test_helper"

class Nexus::Shared::Values::OwnedResourceRegistryTest < ActiveSupport::TestCase
  Entry = Struct.new(:resource_id, :runtime_owner_id, :state, keyword_init: true)

  test "stores looks up and filters entries by runtime owner" do
    registry = Nexus::Shared::Values::OwnedResourceRegistry.new(key_attr: :resource_id)
    first = Entry.new(resource_id: "resource-b", runtime_owner_id: "owner-1", state: "running")
    second = Entry.new(resource_id: "resource-a", runtime_owner_id: "owner-2", state: "stopped")

    registry.store(first)
    registry.store(second)

    assert_equal first, registry.lookup(key: "resource-b")
    assert_equal [second, first], registry.list
    assert_equal [first], registry.list(runtime_owner_id: "owner-1")
  end

  test "projects filtered snapshots while holding the registry boundary" do
    registry = Nexus::Shared::Values::OwnedResourceRegistry.new(key_attr: :resource_id)
    registry.store(Entry.new(resource_id: "resource-b", runtime_owner_id: "owner-1", state: "running"))
    registry.store(Entry.new(resource_id: "resource-a", runtime_owner_id: "owner-2", state: "stopped"))

    projected = registry.project_list(runtime_owner_id: "owner-1") do |entry|
      { "resource_id" => entry.resource_id, "state" => entry.state }
    end

    assert_equal [{ "resource_id" => "resource-b", "state" => "running" }], projected
  end

  test "mutate updates a stored entry and returns the block result" do
    registry = Nexus::Shared::Values::OwnedResourceRegistry.new(key_attr: :resource_id)
    entry = Entry.new(resource_id: "resource-a", runtime_owner_id: "owner-1", state: "running")
    registry.store(entry)

    result = registry.mutate(key: "resource-a") do |stored|
      stored.state = "stopped"
      stored.state
    end

    assert_equal "stopped", result
    assert_equal "stopped", registry.lookup(key: "resource-a").state
  end

  test "project_entry returns a transformed snapshot for a single key" do
    registry = Nexus::Shared::Values::OwnedResourceRegistry.new(key_attr: :resource_id)
    registry.store(Entry.new(resource_id: "resource-a", runtime_owner_id: "owner-1", state: "running"))

    projected = registry.project_entry(key: "resource-a") do |entry|
      { "resource_id" => entry.resource_id, "state" => entry.state }
    end

    assert_equal({ "resource_id" => "resource-a", "state" => "running" }, projected)
  end

  test "captures released snapshots when configured" do
    registry = Nexus::Shared::Values::OwnedResourceRegistry.new(
      key_attr: :resource_id,
      retain_released_snapshots: true
    )
    entry = Entry.new(resource_id: "resource-a", runtime_owner_id: "owner-1", state: "running")
    registry.store(entry)

    registry.capture_and_remove(
      key: "resource-a",
      entry: entry,
      snapshot: { "resource_id" => "resource-a", "state" => "stopped" }
    )

    assert_nil registry.lookup(key: "resource-a")
    assert_equal({ "resource_id" => "resource-a", "state" => "stopped" }, registry.released_snapshot("resource-a"))
  end

  test "clear! returns current entries and clears released snapshots" do
    registry = Nexus::Shared::Values::OwnedResourceRegistry.new(
      key_attr: :resource_id,
      retain_released_snapshots: true
    )
    entry = Entry.new(resource_id: "resource-a", runtime_owner_id: "owner-1", state: "running")
    registry.store(entry)
    registry.capture_released_snapshot(key: "released-a", snapshot: { "resource_id" => "released-a" })

    cleared = registry.clear!

    assert_equal [entry], cleared
    assert_empty registry.list
    assert_nil registry.released_snapshot("released-a")
  end
end
