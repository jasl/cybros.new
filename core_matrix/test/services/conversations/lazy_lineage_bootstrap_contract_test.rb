require "test_helper"

class Conversations::LazyLineageBootstrapContractTest < ActiveSupport::TestCase
  test "bare root creation does not preallocate lineage substrate" do
    context = create_workspace_context!

    conversation = nil
    assert_no_difference(["LineageStore.count", "LineageStoreSnapshot.count", "LineageStoreReference.count"]) do
      conversation = Conversations::CreateRoot.call(
        workspace: context[:workspace],
      )
    end

    assert_nil conversation.reload.lineage_store_reference
  end

  test "automation root creation does not preallocate lineage substrate" do
    context = create_workspace_context!

    conversation = nil
    assert_no_difference(["LineageStore.count", "LineageStoreSnapshot.count", "LineageStoreReference.count"]) do
      conversation = Conversations::CreateAutomationRoot.call(
        workspace: context[:workspace],
      )
    end

    assert_nil conversation.reload.lineage_store_reference
  end

  test "the first lineage write bootstraps the owner store exactly once" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
    )

    assert_difference(
      {
        "LineageStore.count" => 1,
        "LineageStoreSnapshot.count" => 2,
        "LineageStoreReference.count" => 1,
        "LineageStoreEntry.count" => 1,
        "LineageStoreValue.count" => 1,
      }
    ) do
      LineageStores::Set.call(
        conversation: conversation,
        key: "tone",
        typed_value_payload: { "type" => "string", "value" => "direct" }
      )
    end

    visible = LineageStores::GetQuery.call(reference_owner: conversation, key: "tone")

    assert_equal "direct", visible.typed_value_payload.fetch("value")
    assert_equal 1, conversation.reload.lineage_store_reference.lineage_store_snapshot.depth
  end
end
