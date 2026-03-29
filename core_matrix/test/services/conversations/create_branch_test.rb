require "test_helper"

class Conversations::CreateBranchTest < ActiveSupport::TestCase
  test "requires a historical anchor and preserves lineage" do
    context = create_workspace_context!
    root = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    anchor_turn = Turns::StartUserTurn.call(
      conversation: root,
      content: "Anchor input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::CreateBranch.call(parent: root)
    end

    branch = Conversations::CreateBranch.call(
      parent: root,
      historical_anchor_message_id: anchor_turn.selected_input_message_id
    )

    assert branch.branch?
    assert branch.interactive?
    assert branch.active?
    assert_equal root, branch.parent_conversation
    assert_equal anchor_turn.selected_input_message_id, branch.historical_anchor_message_id
    assert_equal [[root.id, branch.id, 1], [branch.id, branch.id, 0]],
      ConversationClosure.where(descendant_conversation: branch)
        .order(depth: :desc)
        .pluck(:ancestor_conversation_id, :descendant_conversation_id, :depth)
  end

  test "reuses the same lineage store with its own reference" do
    context = create_workspace_context!
    root = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    LineageStores::Set.call(
      conversation: root,
      key: "tone",
      typed_value_payload: { "type" => "string", "value" => "direct" }
    )
    anchor_turn = Turns::StartUserTurn.call(
      conversation: root,
      content: "Anchor input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    assert_no_difference(["LineageStoreSnapshot.count", "LineageStoreEntry.count", "LineageStoreValue.count"]) do
      @branch = Conversations::CreateBranch.call(
        parent: root,
        historical_anchor_message_id: anchor_turn.selected_input_message_id
      )
    end

    assert_equal root.lineage_store_reference.lineage_store_snapshot.lineage_store_id,
      @branch.lineage_store_reference.lineage_store_snapshot.lineage_store_id
    refute_equal root.lineage_store_reference.id, @branch.lineage_store_reference.id
    assert_equal "direct",
      LineageStores::GetQuery.call(reference_owner: @branch, key: "tone").typed_value_payload["value"]
  end

  test "rejects automation conversations" do
    context = create_workspace_context!
    automation_root = Conversations::CreateAutomationRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    automation_turn = Turns::StartAutomationTurn.call(
      conversation: automation_root,
      origin_kind: "system_internal",
      origin_payload: {},
      source_ref_type: "AgentDeployment",
      source_ref_id: context[:agent_deployment].public_id,
      idempotency_key: "automation-branch-anchor",
      external_event_key: "automation-branch-anchor",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    automation_anchor = attach_selected_output!(automation_turn, content: "Automation output")

    assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::CreateBranch.call(
        parent: automation_root,
        historical_anchor_message_id: automation_anchor.id
      )
    end
  end

  test "rejects anchors outside the parent conversation history" do
    context = create_workspace_context!
    root = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    other_root = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    foreign_turn = Turns::StartUserTurn.call(
      conversation: other_root,
      content: "Foreign input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::CreateBranch.call(
        parent: root,
        historical_anchor_message_id: foreign_turn.selected_input_message_id
      )
    end

    assert_includes error.record.errors[:historical_anchor_message_id], "must belong to the parent conversation history"
  end

  test "accepts an anchor inherited into the parent transcript history" do
    context = create_workspace_context!
    root = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    root_turn = Turns::StartUserTurn.call(
      conversation: root,
      content: "Root inherited anchor",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    parent_branch = Conversations::CreateBranch.call(
      parent: root,
      historical_anchor_message_id: root_turn.selected_input_message_id
    )

    branch = Conversations::CreateBranch.call(
      parent: parent_branch,
      historical_anchor_message_id: root_turn.selected_input_message_id
    )

    assert_equal parent_branch, branch.parent_conversation
    assert_equal root_turn.selected_input_message_id, branch.historical_anchor_message_id
  end

  test "rejects archived parents" do
    context = create_workspace_context!
    root = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    anchor_turn = Turns::StartUserTurn.call(
      conversation: root,
      content: "Anchor input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    root.update!(lifecycle_state: "archived")

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::CreateBranch.call(parent: root, historical_anchor_message_id: anchor_turn.selected_input_message_id)
    end

    assert_instance_of Conversation, error.record
    assert error.record.branch?
    assert_equal root, error.record.parent_conversation
    assert_equal anchor_turn.selected_input_message_id, error.record.historical_anchor_message_id
    assert_includes error.record.errors[:lifecycle_state], "must be active before branching"
  end
end
