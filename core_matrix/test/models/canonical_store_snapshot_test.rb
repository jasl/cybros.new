require "test_helper"

class CanonicalStoreSnapshotTest < ActiveSupport::TestCase
  test "enforces snapshot depth, base, and store-boundary rules" do
    context = create_workspace_context!
    root_conversation = create_conversation_record!(workspace: context[:workspace])
    canonical_store = create_canonical_store!(
      workspace: context[:workspace],
      root_conversation: root_conversation
    )
    root_snapshot = create_canonical_store_snapshot!(canonical_store: canonical_store, snapshot_kind: "root")

    write_without_base = CanonicalStoreSnapshot.new(
      canonical_store: canonical_store,
      snapshot_kind: "write",
      depth: 1
    )
    write_with_wrong_depth = CanonicalStoreSnapshot.new(
      canonical_store: canonical_store,
      snapshot_kind: "write",
      base_snapshot: root_snapshot,
      depth: 0
    )
    compaction_with_base = CanonicalStoreSnapshot.new(
      canonical_store: canonical_store,
      snapshot_kind: "compaction",
      base_snapshot: root_snapshot,
      depth: 0
    )

    other_conversation = create_conversation_record!(workspace: context[:workspace])
    other_store = create_canonical_store!(
      workspace: context[:workspace],
      root_conversation: other_conversation
    )
    cross_store_write = CanonicalStoreSnapshot.new(
      canonical_store: other_store,
      snapshot_kind: "write",
      base_snapshot: root_snapshot,
      depth: 1
    )

    assert write_without_base.invalid?
    assert_includes write_without_base.errors[:base_snapshot], "must exist for write snapshots"

    assert write_with_wrong_depth.invalid?
    assert_includes write_with_wrong_depth.errors[:depth], "must equal base snapshot depth plus one"

    assert compaction_with_base.invalid?
    assert_includes compaction_with_base.errors[:base_snapshot], "must be blank for root and compaction snapshots"

    assert cross_store_write.invalid?
    assert_includes cross_store_write.errors[:base_snapshot], "must belong to the same canonical store"
  end
end
