require "test_helper"

class Conversations::CreateCheckpointTest < ActiveSupport::TestCase
  test "requires a historical anchor and keeps checkpoint lineage" do
    root = Conversations::CreateRoot.call(workspace: create_workspace_context![:workspace])

    assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::CreateCheckpoint.call(parent: root)
    end

    checkpoint = Conversations::CreateCheckpoint.call(
      parent: root,
      historical_anchor_message_id: 303
    )

    assert checkpoint.checkpoint?
    assert checkpoint.interactive?
    assert checkpoint.active?
    assert_equal root, checkpoint.parent_conversation
    assert_equal 303, checkpoint.historical_anchor_message_id
    assert_equal [[root.id, checkpoint.id, 1], [checkpoint.id, checkpoint.id, 0]],
      ConversationClosure.where(descendant_conversation: checkpoint)
        .order(depth: :desc)
        .pluck(:ancestor_conversation_id, :descendant_conversation_id, :depth)
  end

  test "copies the current snapshot reference without creating store rows" do
    context = create_workspace_context!
    root = Conversations::CreateRoot.call(workspace: context[:workspace])
    CanonicalStores::Set.call(
      conversation: root,
      key: "tone",
      typed_value_payload: { "type" => "string", "value" => "direct" }
    )

    assert_no_difference(["CanonicalStoreSnapshot.count", "CanonicalStoreEntry.count", "CanonicalStoreValue.count"]) do
      @checkpoint = Conversations::CreateCheckpoint.call(
        parent: root,
        historical_anchor_message_id: 303
      )
    end

    assert_equal root.canonical_store_reference.canonical_store_snapshot_id,
      @checkpoint.canonical_store_reference.canonical_store_snapshot_id
    refute_equal root.canonical_store_reference.id, @checkpoint.canonical_store_reference.id
  end

  test "rejects automation conversations" do
    automation_root = Conversations::CreateAutomationRoot.call(
      workspace: create_workspace_context![:workspace]
    )

    assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::CreateCheckpoint.call(
        parent: automation_root,
        historical_anchor_message_id: 303
      )
    end
  end
end
