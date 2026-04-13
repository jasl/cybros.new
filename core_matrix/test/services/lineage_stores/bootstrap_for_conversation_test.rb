require "test_helper"

module LineageStores
end

class LineageStores::BootstrapForConversationTest < ActiveSupport::TestCase
  test "creates a store root snapshot and live reference for the conversation" do
    context = create_workspace_context!
    conversation = create_conversation_record!(workspace: context[:workspace])

    assert_difference(["LineageStore.count", "LineageStoreSnapshot.count", "LineageStoreReference.count"], +1) do
      LineageStores::BootstrapForConversation.call(conversation: conversation)
    end

    reference = conversation.reload.lineage_store_reference

    assert reference.present?
    assert_equal conversation, reference.owner
    assert_nil LineageStore.reflect_on_association(:root_conversation)
    assert_not_nil LineageStore.reflect_on_association(:owner_conversation)
    assert_equal conversation, reference.lineage_store_snapshot.lineage_store.owner_conversation
    assert_equal "root", reference.lineage_store_snapshot.snapshot_kind
    assert_equal 0, reference.lineage_store_snapshot.depth
  end
end
