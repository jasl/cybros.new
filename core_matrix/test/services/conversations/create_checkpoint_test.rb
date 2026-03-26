require "test_helper"

class Conversations::CreateCheckpointTest < ActiveSupport::TestCase
  test "requires a historical anchor and keeps checkpoint lineage" do
    context = create_workspace_context!
    root = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )

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
    root = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
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
    context = create_workspace_context!
    automation_root = Conversations::CreateAutomationRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )

    assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::CreateCheckpoint.call(
        parent: automation_root,
        historical_anchor_message_id: 303
      )
    end
  end

  test "rejects pending delete parents" do
    context = create_workspace_context!
    root = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    root.update!(deletion_state: "pending_delete", deleted_at: Time.current)

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::CreateCheckpoint.call(
        parent: root,
        historical_anchor_message_id: 303
      )
    end

    assert_includes error.record.errors[:deletion_state], "must be retained before checkpointing"
  end
end
