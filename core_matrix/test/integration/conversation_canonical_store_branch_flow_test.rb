require "test_helper"

class ConversationCanonicalStoreBranchFlowTest < ActionDispatch::IntegrationTest
  test "branches share the canonical store but freeze the child snapshot at branch time" do
    context = create_workspace_context!
    root = Conversations::CreateRoot.call(workspace: context[:workspace])
    CanonicalStores::Set.call(
      conversation: root,
      key: "tone",
      typed_value_payload: { "type" => "string", "value" => "direct" }
    )

    branch = Conversations::CreateBranch.call(
      parent: root,
      historical_anchor_message_id: 101
    )

    CanonicalStores::Set.call(
      conversation: root,
      key: "tone",
      typed_value_payload: { "type" => "string", "value" => "parent-updated" }
    )
    CanonicalStores::Set.call(
      conversation: branch,
      key: "tone",
      typed_value_payload: { "type" => "string", "value" => "branch-only" }
    )
    CanonicalStores::Set.call(
      conversation: branch,
      key: "branch_note",
      typed_value_payload: { "type" => "string", "value" => "child" }
    )

    assert_equal root.canonical_store_reference.canonical_store_snapshot.canonical_store_id,
      branch.canonical_store_reference.canonical_store_snapshot.canonical_store_id
    refute_equal root.canonical_store_reference.id, branch.canonical_store_reference.id
    assert_equal "parent-updated",
      CanonicalStores::GetQuery.call(reference_owner: root, key: "tone").typed_value_payload["value"]
    assert_equal "branch-only",
      CanonicalStores::GetQuery.call(reference_owner: branch, key: "tone").typed_value_payload["value"]
    assert_equal "child",
      CanonicalStores::GetQuery.call(reference_owner: branch, key: "branch_note").typed_value_payload["value"]
    assert_nil CanonicalStores::GetQuery.call(reference_owner: root, key: "branch_note")
  end
end
