require "test_helper"

class Conversations::CreateForkTest < ActiveSupport::TestCase
  test "creates a fork without requiring transcript cloning" do
    context = create_workspace_context!
    root = Conversations::CreateRoot.call(
      workspace: context[:workspace],
    )
    anchor_turn = Turns::StartUserTurn.call(
      conversation: root,
      content: "Fork anchor",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    fork = Conversations::CreateFork.call(
      parent: root,
      historical_anchor_message_id: anchor_turn.selected_input_message_id
    )

    assert fork.fork?
    assert fork.interactive?
    assert fork.active?
    assert_equal root, fork.parent_conversation
    assert_equal anchor_turn.selected_input_message_id, fork.historical_anchor_message_id
    assert_equal [[root.id, fork.id, 1], [fork.id, fork.id, 0]],
      ConversationClosure.where(descendant_conversation: fork)
        .order(depth: :desc)
        .pluck(:ancestor_conversation_id, :descendant_conversation_id, :depth)
  end

  test "copies the current snapshot reference without duplicating keys" do
    context = create_workspace_context!
    root = Conversations::CreateRoot.call(
      workspace: context[:workspace],
    )
    LineageStores::Set.call(
      conversation: root,
      key: "tone",
      typed_value_payload: { "type" => "string", "value" => "direct" }
    )
    anchor_turn = Turns::StartUserTurn.call(
      conversation: root,
      content: "Fork anchor",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    assert_no_difference(["LineageStoreSnapshot.count", "LineageStoreEntry.count", "LineageStoreValue.count"]) do
      @fork = Conversations::CreateFork.call(parent: root, historical_anchor_message_id: anchor_turn.selected_input_message_id)
    end

    assert_equal root.lineage_store_reference.lineage_store_snapshot_id,
      @fork.lineage_store_reference.lineage_store_snapshot_id
    refute_equal root.lineage_store_reference.id, @fork.lineage_store_reference.id
  end

  test "rejects automation conversations" do
    context = create_workspace_context!
    automation_root = Conversations::CreateAutomationRoot.call(
      workspace: context[:workspace],
    )

    assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::CreateFork.call(parent: automation_root)
    end
  end

  test "rejects invalid optional anchors outside the parent conversation history" do
    context = create_workspace_context!
    root = Conversations::CreateRoot.call(
      workspace: context[:workspace],
    )
    other_root = Conversations::CreateRoot.call(
      workspace: context[:workspace],
    )
    foreign_turn = Turns::StartUserTurn.call(
      conversation: other_root,
      content: "Foreign fork anchor",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::CreateFork.call(
        parent: root,
        historical_anchor_message_id: foreign_turn.selected_input_message_id
      )
    end

    assert_instance_of Conversation, error.record
    assert error.record.fork?
    assert_equal root, error.record.parent_conversation
    assert_equal foreign_turn.selected_input_message_id, error.record.historical_anchor_message_id
    assert_includes error.record.errors[:historical_anchor_message_id], "must belong to the parent conversation history"
  end

  test "accepts an optional anchor inherited into the parent transcript history" do
    context = create_workspace_context!
    root = Conversations::CreateRoot.call(
      workspace: context[:workspace],
    )
    root_turn = Turns::StartUserTurn.call(
      conversation: root,
      content: "Root inherited fork anchor",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    branch = Conversations::CreateBranch.call(
      parent: root,
      historical_anchor_message_id: root_turn.selected_input_message_id
    )

    fork = Conversations::CreateFork.call(
      parent: branch,
      historical_anchor_message_id: root_turn.selected_input_message_id
    )

    assert_equal branch, fork.parent_conversation
    assert_equal root_turn.selected_input_message_id, fork.historical_anchor_message_id
  end

  test "rejects parents while close is in progress" do
    context = create_workspace_context!
    root = Conversations::CreateRoot.call(
      workspace: context[:workspace],
    )
    ConversationCloseOperation.create!(
      installation: root.installation,
      conversation: root,
      intent_kind: "archive",
      lifecycle_state: "requested",
      requested_at: Time.current,
      summary_payload: {}
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::CreateFork.call(parent: root)
    end

    assert_instance_of Conversation, error.record
    assert error.record.fork?
    assert_equal root, error.record.parent_conversation
    assert_includes error.record.errors[:base], "must not create child conversations while close is in progress"
  end
end
