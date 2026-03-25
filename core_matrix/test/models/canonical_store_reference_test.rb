require "test_helper"

class CanonicalStoreReferenceTest < ActiveSupport::TestCase
  test "enforces one active reference per owner" do
    context = create_workspace_context!
    conversation = create_conversation_record!(workspace: context[:workspace])
    canonical_store = create_canonical_store!(
      workspace: context[:workspace],
      root_conversation: conversation
    )
    root_snapshot = create_canonical_store_snapshot!(canonical_store: canonical_store, snapshot_kind: "root")
    write_snapshot = create_canonical_store_snapshot!(
      canonical_store: canonical_store,
      snapshot_kind: "write",
      base_snapshot: root_snapshot,
      depth: 1
    )

    create_canonical_store_reference!(
      canonical_store_snapshot: root_snapshot,
      owner: conversation
    )

    duplicate = CanonicalStoreReference.new(
      canonical_store_snapshot: write_snapshot,
      owner: conversation
    )

    assert duplicate.invalid?
    assert_includes duplicate.errors[:owner_id], "has already been taken"
  end
end
