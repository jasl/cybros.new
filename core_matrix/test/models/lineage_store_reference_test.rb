require "test_helper"

class LineageStoreReferenceTest < ActiveSupport::TestCase
  test "enforces one active reference per owner" do
    context = create_workspace_context!
    conversation = create_conversation_record!(workspace: context[:workspace])
    lineage_store = create_lineage_store!(
      workspace: context[:workspace],
      root_conversation: conversation
    )
    root_snapshot = create_lineage_store_snapshot!(lineage_store: lineage_store, snapshot_kind: "root")
    write_snapshot = create_lineage_store_snapshot!(
      lineage_store: lineage_store,
      snapshot_kind: "write",
      base_snapshot: root_snapshot,
      depth: 1
    )

    create_lineage_store_reference!(
      lineage_store_snapshot: root_snapshot,
      owner: conversation
    )

    duplicate = LineageStoreReference.new(
      lineage_store_snapshot: write_snapshot,
      owner: conversation
    )

    assert duplicate.invalid?
    assert_includes duplicate.errors[:owner_id], "has already been taken"
  end
end
