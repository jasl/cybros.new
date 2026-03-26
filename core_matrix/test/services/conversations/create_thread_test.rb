require "test_helper"

class Conversations::CreateThreadTest < ActiveSupport::TestCase
  test "creates a thread without requiring transcript cloning" do
    context = create_workspace_context!
    root = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )

    thread = Conversations::CreateThread.call(
      parent: root,
      historical_anchor_message_id: 202
    )

    assert thread.thread?
    assert thread.interactive?
    assert thread.active?
    assert_equal root, thread.parent_conversation
    assert_equal 202, thread.historical_anchor_message_id
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

    assert_no_difference(["CanonicalStoreSnapshot.count", "CanonicalStoreEntry.count", "CanonicalStoreValue.count"]) do
      @thread = Conversations::CreateThread.call(parent: root, historical_anchor_message_id: 202)
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
end
