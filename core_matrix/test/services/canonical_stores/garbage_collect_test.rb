require "test_helper"

class CanonicalStores::GarbageCollectTest < ActiveSupport::TestCase
  test "preserves snapshots still reachable from a child conversation reference" do
    context = build_canonical_store_context!
    CanonicalStores::Set.call(
      conversation: context[:conversation],
      key: "tone",
      typed_value_payload: { "type" => "string", "value" => "direct" }
    )
    branch = Conversations::CreateBranch.call(
      parent: context[:conversation],
      historical_anchor_message_id: context[:turn].selected_input_message_id
    )

    Conversations::RequestDeletion.call(conversation: context[:conversation])
    Conversations::FinalizeDeletion.call(conversation: context[:conversation].reload)

    assert_no_difference("CanonicalStore.count") do
      CanonicalStores::GarbageCollect.call
    end

    assert_equal "direct",
      CanonicalStores::GetQuery.call(reference_owner: branch, key: "tone").typed_value_payload["value"]
  end

  test "deletes unreachable snapshots entries values and stores once the last reference is gone" do
    context = build_canonical_store_context!
    CanonicalStores::Set.call(
      conversation: context[:conversation],
      key: "tone",
      typed_value_payload: { "type" => "string", "value" => "direct" }
    )

    Conversations::RequestDeletion.call(conversation: context[:conversation])
    Conversations::FinalizeDeletion.call(conversation: context[:conversation].reload)

    CanonicalStores::GarbageCollect.call

    assert_equal 0, CanonicalStore.where(id: context[:canonical_store].id).count
    assert_equal 0, CanonicalStoreSnapshot.where(canonical_store: context[:canonical_store]).count
    assert_equal 0, CanonicalStoreEntry.count
    assert_equal 0, CanonicalStoreValue.count
  end

  test "reconciles unfinished delete close operations after removing the root store blocker" do
    context = build_canonical_store_context!

    Conversations::RequestDeletion.call(conversation: context[:conversation])
    finalized = Conversations::FinalizeDeletion.call(conversation: context[:conversation].reload)
    close_operation = finalized.reload.conversation_close_operations.order(:created_at).last

    assert_equal "disposing", close_operation.lifecycle_state
    assert_equal true, close_operation.summary_payload.dig("dependencies", "root_store_blocker")

    CanonicalStores::GarbageCollect.call

    assert_equal "completed", close_operation.reload.lifecycle_state
    assert_not_nil close_operation.completed_at
    assert_equal false, close_operation.summary_payload.dig("dependencies", "root_store_blocker")
  end
end
