require "test_helper"

class Conversations::CreateThreadTest < ActiveSupport::TestCase
  test "creates a thread without requiring transcript cloning" do
    context = create_workspace_context!
    root = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    anchor_turn = Turns::StartUserTurn.call(
      conversation: root,
      content: "Thread anchor",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    thread = Conversations::CreateThread.call(
      parent: root,
      historical_anchor_message_id: anchor_turn.selected_input_message_id
    )

    assert thread.thread?
    assert thread.interactive?
    assert thread.active?
    assert_equal root, thread.parent_conversation
    assert_equal anchor_turn.selected_input_message_id, thread.historical_anchor_message_id
    assert_equal [[root.id, thread.id, 1], [thread.id, thread.id, 0]],
      ConversationClosure.where(descendant_conversation: thread)
        .order(depth: :desc)
        .pluck(:ancestor_conversation_id, :descendant_conversation_id, :depth)
  end

  test "copies the current snapshot reference without duplicating keys" do
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
    anchor_turn = Turns::StartUserTurn.call(
      conversation: root,
      content: "Thread anchor",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    assert_no_difference(["CanonicalStoreSnapshot.count", "CanonicalStoreEntry.count", "CanonicalStoreValue.count"]) do
      @thread = Conversations::CreateThread.call(parent: root, historical_anchor_message_id: anchor_turn.selected_input_message_id)
    end

    assert_equal root.canonical_store_reference.canonical_store_snapshot_id,
      @thread.canonical_store_reference.canonical_store_snapshot_id
    refute_equal root.canonical_store_reference.id, @thread.canonical_store_reference.id
  end

  test "rejects automation conversations" do
    context = create_workspace_context!
    automation_root = Conversations::CreateAutomationRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )

    assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::CreateThread.call(parent: automation_root)
    end
  end

  test "rejects invalid optional anchors outside the parent conversation history" do
    context = create_workspace_context!
    root = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    other_root = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    foreign_turn = Turns::StartUserTurn.call(
      conversation: other_root,
      content: "Foreign thread anchor",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::CreateThread.call(
        parent: root,
        historical_anchor_message_id: foreign_turn.selected_input_message_id
      )
    end

    assert_instance_of Conversation, error.record
    assert error.record.thread?
    assert_equal root, error.record.parent_conversation
    assert_equal foreign_turn.selected_input_message_id, error.record.historical_anchor_message_id
    assert_includes error.record.errors[:historical_anchor_message_id], "must belong to the parent conversation history"
  end

  test "accepts an optional anchor inherited into the parent transcript history" do
    context = create_workspace_context!
    root = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    root_turn = Turns::StartUserTurn.call(
      conversation: root,
      content: "Root inherited thread anchor",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    branch = Conversations::CreateBranch.call(
      parent: root,
      historical_anchor_message_id: root_turn.selected_input_message_id
    )

    thread = Conversations::CreateThread.call(
      parent: branch,
      historical_anchor_message_id: root_turn.selected_input_message_id
    )

    assert_equal branch, thread.parent_conversation
    assert_equal root_turn.selected_input_message_id, thread.historical_anchor_message_id
  end

  test "rejects parents while close is in progress" do
    context = create_workspace_context!
    root = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
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
      Conversations::CreateThread.call(parent: root)
    end

    assert_includes error.record.errors[:base], "must not create child conversations while close is in progress"
  end
end
