require "test_helper"

module CanonicalStores
end

class CanonicalStores::BootstrapForConversationTest < ActiveSupport::TestCase
  test "creates a store root snapshot and live reference for the conversation" do
    context = create_workspace_context!
    conversation = create_conversation_record!(workspace: context[:workspace])

    assert_difference(["CanonicalStore.count", "CanonicalStoreSnapshot.count", "CanonicalStoreReference.count"], +1) do
      CanonicalStores::BootstrapForConversation.call(conversation: conversation)
    end

    reference = conversation.reload.canonical_store_reference

    assert reference.present?
    assert_equal conversation, reference.owner
    assert_equal conversation, reference.canonical_store_snapshot.canonical_store.root_conversation
    assert_equal "root", reference.canonical_store_snapshot.snapshot_kind
    assert_equal 0, reference.canonical_store_snapshot.depth
  end
end
