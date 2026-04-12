require "test_helper"

class Conversations::CreateRootTest < ActiveSupport::TestCase
  test "creates an active interactive root conversation with a self closure" do
    context = create_workspace_context!

    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
    )

    assert_equal context[:installation], conversation.installation
    assert_equal context[:workspace], conversation.workspace
    assert conversation.root?
    assert conversation.interactive?
    assert conversation.active?
    assert conversation.retained?
    assert_nil conversation.parent_conversation
    assert_nil conversation.historical_anchor_message_id
    assert_equal conversation.current_execution_epoch, conversation.execution_epochs.order(:sequence).last
    assert_equal context[:execution_runtime], conversation.current_execution_runtime
    assert_equal "ready", conversation.execution_continuity_state
    assert_equal context[:execution_runtime], conversation.current_execution_epoch.execution_runtime
    assert_equal "root", conversation.lineage_store_reference.lineage_store_snapshot.snapshot_kind
    assert_equal [[conversation.id, conversation.id, 0]],
      ConversationClosure.where(descendant_conversation: conversation)
        .pluck(:ancestor_conversation_id, :descendant_conversation_id, :depth)
  end

  test "accepts an explicit initial execution runtime override" do
    context = create_workspace_context!
    override_runtime = create_execution_runtime!(installation: context[:installation], display_name: "Cloud Runtime")
    create_execution_runtime_connection!(installation: context[:installation], execution_runtime: override_runtime)

    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: override_runtime
    )

    assert_equal override_runtime, conversation.current_execution_runtime
    assert_equal override_runtime, conversation.current_execution_epoch.execution_runtime
  end
end
