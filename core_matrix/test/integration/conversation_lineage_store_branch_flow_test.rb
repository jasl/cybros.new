require "test_helper"

class ConversationLineageStoreBranchFlowTest < ActionDispatch::IntegrationTest
  test "branches share the lineage store but freeze the child snapshot at branch time" do
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
      content: "Root input",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    branch = Conversations::CreateBranch.call(
      parent: root,
      historical_anchor_message_id: anchor_turn.selected_input_message_id
    )

    LineageStores::Set.call(
      conversation: root,
      key: "tone",
      typed_value_payload: { "type" => "string", "value" => "parent-updated" }
    )
    LineageStores::Set.call(
      conversation: branch,
      key: "tone",
      typed_value_payload: { "type" => "string", "value" => "branch-only" }
    )
    LineageStores::Set.call(
      conversation: branch,
      key: "branch_note",
      typed_value_payload: { "type" => "string", "value" => "child" }
    )

    assert_equal root.lineage_store_reference.lineage_store_snapshot.lineage_store_id,
      branch.lineage_store_reference.lineage_store_snapshot.lineage_store_id
    refute_equal root.lineage_store_reference.id, branch.lineage_store_reference.id
    assert_equal "parent-updated",
      LineageStores::GetQuery.call(reference_owner: root, key: "tone").typed_value_payload["value"]
    assert_equal "branch-only",
      LineageStores::GetQuery.call(reference_owner: branch, key: "tone").typed_value_payload["value"]
    assert_equal "child",
      LineageStores::GetQuery.call(reference_owner: branch, key: "branch_note").typed_value_payload["value"]
    assert_nil LineageStores::GetQuery.call(reference_owner: root, key: "branch_note")
  end
end
