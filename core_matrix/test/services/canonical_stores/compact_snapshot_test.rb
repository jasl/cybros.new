require "test_helper"

module CanonicalStores
end

class CanonicalStores::CompactSnapshotTest < ActiveSupport::TestCase
  test "rewrites the visible key set into a depth zero compaction snapshot" do
    context = build_canonical_store_context!
    CanonicalStores::Set.call(
      conversation: context[:conversation],
      key: "alpha",
      typed_value_payload: { "type" => "string", "value" => "A" }
    )
    CanonicalStores::Set.call(
      conversation: context[:conversation],
      key: "beta",
      typed_value_payload: { "type" => "string", "value" => "B" }
    )
    CanonicalStores::DeleteKey.call(conversation: context[:conversation], key: "beta")

    assert_difference("CanonicalStoreSnapshot.count", +1) do
      CanonicalStores::CompactSnapshot.call(conversation: context[:conversation])
    end

    current_snapshot = context[:conversation].reload.canonical_store_reference.canonical_store_snapshot
    visible_keys = CanonicalStores::ListKeysQuery.call(
      reference_owner: context[:conversation],
      cursor: nil,
      limit: 20
    ).items.map(&:key)

    assert_equal "compaction", current_snapshot.snapshot_kind
    assert_equal 0, current_snapshot.depth
    assert_nil current_snapshot.base_snapshot
    assert_equal ["alpha"], visible_keys
    assert_equal ["alpha"], current_snapshot.canonical_store_entries.order(:key).pluck(:key)
  end
end
