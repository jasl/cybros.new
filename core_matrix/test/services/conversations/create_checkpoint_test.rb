require "test_helper"

class Conversations::CreateCheckpointTest < ActiveSupport::TestCase
  test "requires a historical anchor and keeps checkpoint lineage" do
    context = create_workspace_context!
    root = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_snapshot: context[:agent_snapshot]
    )
    anchor_turn = Turns::StartUserTurn.call(
      conversation: root,
      content: "Checkpoint anchor",
      agent_snapshot: context[:agent_snapshot],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::CreateCheckpoint.call(parent: root)
    end

    checkpoint = Conversations::CreateCheckpoint.call(
      parent: root,
      historical_anchor_message_id: anchor_turn.selected_input_message_id
    )

    assert checkpoint.checkpoint?
    assert checkpoint.interactive?
    assert checkpoint.active?
    assert_equal root, checkpoint.parent_conversation
    assert_equal anchor_turn.selected_input_message_id, checkpoint.historical_anchor_message_id
    assert_equal [[root.id, checkpoint.id, 1], [checkpoint.id, checkpoint.id, 0]],
      ConversationClosure.where(descendant_conversation: checkpoint)
        .order(depth: :desc)
        .pluck(:ancestor_conversation_id, :descendant_conversation_id, :depth)
  end

  test "copies the current snapshot reference without creating store rows" do
    context = create_workspace_context!
    root = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_snapshot: context[:agent_snapshot]
    )
    LineageStores::Set.call(
      conversation: root,
      key: "tone",
      typed_value_payload: { "type" => "string", "value" => "direct" }
    )
    anchor_turn = Turns::StartUserTurn.call(
      conversation: root,
      content: "Checkpoint anchor",
      agent_snapshot: context[:agent_snapshot],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    assert_no_difference(["LineageStoreSnapshot.count", "LineageStoreEntry.count", "LineageStoreValue.count"]) do
      @checkpoint = Conversations::CreateCheckpoint.call(
        parent: root,
        historical_anchor_message_id: anchor_turn.selected_input_message_id
      )
    end

    assert_equal root.lineage_store_reference.lineage_store_snapshot_id,
      @checkpoint.lineage_store_reference.lineage_store_snapshot_id
    refute_equal root.lineage_store_reference.id, @checkpoint.lineage_store_reference.id
  end

  test "rejects automation conversations" do
    context = create_workspace_context!
    automation_root = Conversations::CreateAutomationRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_snapshot: context[:agent_snapshot]
    )
    automation_turn = Turns::StartAutomationTurn.call(
      conversation: automation_root,
      origin_kind: "system_internal",
      origin_payload: {},
      source_ref_type: "AgentSnapshot",
      source_ref_id: context[:agent_snapshot].public_id,
      idempotency_key: "automation-checkpoint-anchor",
      external_event_key: "automation-checkpoint-anchor",
      agent_snapshot: context[:agent_snapshot],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    automation_anchor = attach_selected_output!(automation_turn, content: "Automation output")

    assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::CreateCheckpoint.call(
        parent: automation_root,
        historical_anchor_message_id: automation_anchor.id
      )
    end
  end

  test "rejects anchors outside the parent conversation history" do
    context = create_workspace_context!
    root = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_snapshot: context[:agent_snapshot]
    )
    other_root = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_snapshot: context[:agent_snapshot]
    )
    foreign_turn = Turns::StartUserTurn.call(
      conversation: other_root,
      content: "Foreign checkpoint anchor",
      agent_snapshot: context[:agent_snapshot],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::CreateCheckpoint.call(
        parent: root,
        historical_anchor_message_id: foreign_turn.selected_input_message_id
      )
    end

    assert_instance_of Conversation, error.record
    assert error.record.checkpoint?
    assert_equal root, error.record.parent_conversation
    assert_equal foreign_turn.selected_input_message_id, error.record.historical_anchor_message_id
    assert_includes error.record.errors[:historical_anchor_message_id], "must belong to the parent conversation history"
  end

  test "accepts an anchor inherited into the parent transcript history" do
    context = create_workspace_context!
    root = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_snapshot: context[:agent_snapshot]
    )
    root_turn = Turns::StartUserTurn.call(
      conversation: root,
      content: "Root inherited checkpoint anchor",
      agent_snapshot: context[:agent_snapshot],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    branch = Conversations::CreateBranch.call(
      parent: root,
      historical_anchor_message_id: root_turn.selected_input_message_id
    )

    checkpoint = Conversations::CreateCheckpoint.call(
      parent: branch,
      historical_anchor_message_id: root_turn.selected_input_message_id
    )

    assert_equal branch, checkpoint.parent_conversation
    assert_equal root_turn.selected_input_message_id, checkpoint.historical_anchor_message_id
  end

  test "rejects pending delete parents" do
    context = create_workspace_context!
    root = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_snapshot: context[:agent_snapshot]
    )
    anchor_turn = Turns::StartUserTurn.call(
      conversation: root,
      content: "Checkpoint anchor",
      agent_snapshot: context[:agent_snapshot],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    root.update!(deletion_state: "pending_delete", deleted_at: Time.current)

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::CreateCheckpoint.call(
        parent: root,
        historical_anchor_message_id: anchor_turn.selected_input_message_id
      )
    end

    assert_instance_of Conversation, error.record
    assert error.record.checkpoint?
    assert_equal root, error.record.parent_conversation
    assert_equal anchor_turn.selected_input_message_id, error.record.historical_anchor_message_id
    assert_includes error.record.errors[:deletion_state], "must be retained before checkpointing"
  end
end
