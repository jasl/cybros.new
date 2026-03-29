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
    previous_snapshot = context[:conversation].reload.lineage_store_reference.lineage_store_snapshot
    alpha_value_id = LineageStoreEntry
      .joins(:lineage_store_snapshot)
      .where(
        lineage_store_snapshots: { lineage_store_id: previous_snapshot.lineage_store_id },
        key: "alpha",
        entry_kind: "set"
      )
      .order(:id)
      .pick(:lineage_store_value_id)

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
    assert_equal previous_snapshot.lineage_store_id, current_snapshot.lineage_store_id
    assert_equal ["alpha"], visible_keys
    assert_equal ["alpha"], current_snapshot.lineage_store_entries.order(:key).pluck(:key)
    assert_equal alpha_value_id, current_snapshot.lineage_store_entries.find_by!(key: "alpha").lineage_store_value_id
    assert_equal [], current_snapshot.lineage_store_entries.where(entry_kind: "tombstone").pluck(:key)
    refute current_snapshot.lineage_store_entries.exists?(key: "beta")
  end
end
