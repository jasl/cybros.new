require "test_helper"

class Conversations::ChildLineageBootstrapWeightTest < ActiveSupport::TestCase
  test "branch creation with no parent lineage reference creates no lineage rows" do
    context = create_workspace_context!
    root = Conversations::CreateRoot.call(
      workspace: context[:workspace],
    )
    anchor_turn = Turns::StartUserTurn.call(
      conversation: root,
      content: "Anchor input",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    branch = nil
    assert_no_difference(["LineageStore.count", "LineageStoreSnapshot.count", "LineageStoreReference.count"]) do
      branch = Conversations::CreateBranch.call(
        parent: root,
        historical_anchor_message_id: anchor_turn.selected_input_message_id
      )
    end

    assert_nil root.reload.lineage_store_reference
    assert_nil branch.reload.lineage_store_reference
  end

  test "branch creation with parent lineage creates exactly one child reference" do
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
      content: "Anchor input",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    branch = nil
    assert_no_difference(["LineageStore.count", "LineageStoreSnapshot.count", "LineageStoreEntry.count", "LineageStoreValue.count"]) do
      assert_difference("LineageStoreReference.count", +1) do
        branch = Conversations::CreateBranch.call(
          parent: root,
          historical_anchor_message_id: anchor_turn.selected_input_message_id
        )
      end
    end

    assert_equal root.lineage_store_reference.lineage_store_snapshot_id,
      branch.reload.lineage_store_reference.lineage_store_snapshot_id
  end
end
