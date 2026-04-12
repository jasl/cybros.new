require "test_helper"

class ConversationSafeDeletionFlowTest < ActionDispatch::IntegrationTest
  test "deleted conversations disappear from agent api user inbox and publication access" do
    context = build_human_interaction_context!
    registration = register_machine_api_for_context!(context)
    HumanInteractions::Request.call(
      request_type: "ApprovalRequest",
      workflow_node: context[:workflow_node],
      blocking: true,
      request_payload: { "approval_scope" => "publish" }
    )
    publication = Publications::PublishLive.call(
      conversation: context[:conversation],
      actor: context[:user],
      visibility_mode: "external_public"
    )

    Conversations::RequestDeletion.call(conversation: context[:conversation])

    get "/agent_api/conversation_variables/resolve",
      params: {
        workspace_id: context[:workspace].public_id,
        conversation_id: context[:conversation].public_id,
      },
      headers: agent_api_headers(registration[:agent_connection_credential])

    assert_response :not_found
    assert_equal [], HumanInteractions::OpenForUserQuery.call(user: context[:user])
    assert_raises(ActiveRecord::RecordInvalid) do
      Publications::RecordAccess.call(publication: publication.reload, request_metadata: { "ip" => "127.0.0.1" })
    end
  end

  test "pending delete conversations reject new conversation mutations" do
    context = build_lineage_store_context!
    context[:conversation].update!(deletion_state: "pending_delete", deleted_at: Time.current)

    assert_raises(ActiveRecord::RecordInvalid) do
      Turns::StartUserTurn.call(
        conversation: context[:conversation],
        content: "Blocked input",
        agent_definition_version: context[:agent_definition_version],
        resolved_config_snapshot: {},
        resolved_model_selection_snapshot: {}
      )
    end

    assert_raises(ActiveRecord::RecordInvalid) do
      Turns::QueueFollowUp.call(
        conversation: context[:conversation],
        content: "Blocked follow up",
        agent_definition_version: context[:agent_definition_version],
        resolved_config_snapshot: {},
        resolved_model_selection_snapshot: {}
      )
    end

    assert_raises(ActiveRecord::RecordInvalid) do
      LineageStores::Set.call(
        conversation: context[:conversation],
        key: "tone",
        typed_value_payload: { "type" => "string", "value" => "direct" }
      )
    end

    assert_raises(ActiveRecord::RecordInvalid) do
      LineageStores::DeleteKey.call(
        conversation: context[:conversation],
        key: "tone"
      )
    end

    assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::CreateBranch.call(parent: context[:conversation])
    end

    assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::CreateCheckpoint.call(parent: context[:conversation], historical_anchor_message_id: context[:turn].selected_input_message_id)
    end

    assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::CreateFork.call(parent: context[:conversation])
    end
  end

  test "deleting a parent conversation does not cancel active child turns and purge stays blocked by lineage" do
    context = create_workspace_context!
    parent = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version]
    )
    child = Conversations::CreateFork.call(parent: parent)
    child_turn = Turns::StartUserTurn.call(
      conversation: child,
      content: "Child still running",
      agent_definition_version: context[:agent_definition_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    deleted_parent = Conversations::RequestDeletion.call(conversation: parent)
    finalized_parent = Conversations::FinalizeDeletion.call(conversation: deleted_parent.reload)

    assert finalized_parent.deleted?
    assert child.reload.retained?
    assert child_turn.reload.active?

    assert_no_difference("Conversation.count") do
      Conversations::PurgeDeleted.call(conversation: finalized_parent.reload)
    end

    assert Conversation.exists?(parent.id)
  end
end
