require "test_helper"

class LineageStoreSnapshotTest < ActiveSupport::TestCase
  test "enforces snapshot depth, base, and store-boundary rules" do
    context = create_workspace_context!
    root_conversation = create_conversation_record!(workspace: context[:workspace])
    lineage_store = create_lineage_store!(
      workspace: context[:workspace],
      owner_conversation: root_conversation
    )
    root_snapshot = create_lineage_store_snapshot!(lineage_store: lineage_store, snapshot_kind: "root")

    write_without_base = LineageStoreSnapshot.new(
      lineage_store: lineage_store,
      snapshot_kind: "write",
      depth: 1
    )
    write_with_wrong_depth = LineageStoreSnapshot.new(
      lineage_store: lineage_store,
      snapshot_kind: "write",
      base_snapshot: root_snapshot,
      depth: 0
    )
    compaction_with_base = LineageStoreSnapshot.new(
      lineage_store: lineage_store,
      snapshot_kind: "compaction",
      base_snapshot: root_snapshot,
      depth: 0
    )

    other_conversation = create_conversation_record!(workspace: context[:workspace])
    other_store = create_lineage_store!(
      workspace: context[:workspace],
      owner_conversation: other_conversation
    )
    cross_store_write = LineageStoreSnapshot.new(
      lineage_store: other_store,
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
    assert_includes cross_store_write.errors[:base_snapshot], "must belong to the same lineage store"
  end
end
