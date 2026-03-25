require "test_helper"

class Conversations::FinalizeDeletionTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "marks a pending deletion deleted, removes the canonical store reference, and enqueues gc" do
    conversation = Conversations::CreateRoot.call(workspace: create_workspace_context![:workspace])
    Conversations::RequestDeletion.call(conversation: conversation)

    assert_enqueued_with(job: CanonicalStores::GarbageCollectJob) do
      finalized = Conversations::FinalizeDeletion.call(conversation: conversation.reload)

      assert finalized.deleted?
      assert_nil finalized.canonical_store_reference
      assert_not_nil finalized.deleted_at
    end
  end

  test "rejects finalization while active work remains" do
    context = build_canonical_variable_context!
    context[:conversation].update!(deletion_state: "pending_delete", deleted_at: Time.current)

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::FinalizeDeletion.call(conversation: context[:conversation])
    end

    assert_includes error.record.errors[:base], "must not have active turns before final deletion"
  end
end
