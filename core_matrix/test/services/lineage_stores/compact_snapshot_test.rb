require "test_helper"

module LineageStores
end

class LineageStores::CompactSnapshotTest < ActiveSupport::TestCase
  test "rewrites the visible key set into a depth zero compaction snapshot" do
    context = build_lineage_store_context!
    LineageStores::Set.call(
      conversation: context[:conversation],
      key: "alpha",
      typed_value_payload: { "type" => "string", "value" => "A" }
    )
    LineageStores::Set.call(
      conversation: context[:conversation],
      key: "beta",
      typed_value_payload: { "type" => "string", "value" => "B" }
    )
    LineageStores::DeleteKey.call(conversation: context[:conversation], key: "beta")

    assert_difference("LineageStoreSnapshot.count", +1) do
      LineageStores::CompactSnapshot.call(conversation: context[:conversation])
    end

    current_snapshot = context[:conversation].reload.lineage_store_reference.lineage_store_snapshot
    visible_keys = LineageStores::ListKeysQuery.call(
      reference_owner: context[:conversation],
      cursor: nil,
      limit: 20
    ).items.map(&:key)

    assert_equal "compaction", current_snapshot.snapshot_kind
    assert_equal 0, current_snapshot.depth
    assert_nil current_snapshot.base_snapshot
    assert_equal ["alpha"], visible_keys
    assert_equal ["alpha"], current_snapshot.lineage_store_entries.order(:key).pluck(:key)
  end
end
