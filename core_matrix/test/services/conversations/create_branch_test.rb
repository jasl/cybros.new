require "test_helper"

class Conversations::CreateBranchTest < ActiveSupport::TestCase
  test "requires a historical anchor and preserves lineage" do
    context = create_workspace_context!
    root = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )

    assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::CreateBranch.call(parent: root)
    end

    branch = Conversations::CreateBranch.call(
      parent: root,
      historical_anchor_message_id: 101
    )

    assert branch.branch?
    assert branch.interactive?
    assert branch.active?
    assert_equal root, branch.parent_conversation
    assert_equal 101, branch.historical_anchor_message_id
    assert_equal [[root.id, branch.id, 1], [branch.id, branch.id, 0]],
      ConversationClosure.where(descendant_conversation: branch)
        .order(depth: :desc)
        .pluck(:ancestor_conversation_id, :descendant_conversation_id, :depth)
  end

  test "reuses the same canonical store with its own reference" do
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
      @branch = Conversations::CreateBranch.call(
        parent: root,
        historical_anchor_message_id: 101
      )
    end

    assert_equal root.canonical_store_reference.canonical_store_snapshot.canonical_store_id,
      @branch.canonical_store_reference.canonical_store_snapshot.canonical_store_id
    refute_equal root.canonical_store_reference.id, @branch.canonical_store_reference.id
    assert_equal "direct",
      CanonicalStores::GetQuery.call(reference_owner: @branch, key: "tone").typed_value_payload["value"]
  end

  test "rejects automation conversations" do
    context = create_workspace_context!
    automation_root = Conversations::CreateAutomationRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )

    assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::CreateBranch.call(
        parent: automation_root,
        historical_anchor_message_id: 101
      )
    end
  end
end
