require "test_helper"

class Conversations::PurgePlanTest < ActiveSupport::TestCase
  test "removes owned rows so remaining_owned_rows? flips false after execute" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Purge plan input",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    workflow_run = create_workflow_run!(turn: turn)
    create_workflow_node!(workflow_run: workflow_run)
    attach_selected_output!(turn, content: "Purge plan output")
    plan = Conversations::PurgePlan.new(conversation: conversation)

    assert plan.remaining_owned_rows?

    plan.execute!

    assert_not plan.remaining_owned_rows?
    assert_not Message.exists?(turn.selected_input_message_id)
    assert_not WorkflowRun.exists?(workflow_run.id)
    assert_not Turn.exists?(turn.id)
  end

  test "removes derived diagnostics, supervision, capability, and export rows before the conversation is deleted" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Derived cleanup input",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    workflow_run = create_workflow_run!(turn: turn)
    create_workflow_node!(workflow_run: workflow_run)
    attach_selected_output!(turn, content: "Derived cleanup output")

    conversation_diagnostics_snapshot = ConversationDiagnosticsSnapshot.create!(
      installation: context[:installation],
      conversation: conversation,
      lifecycle_state: "completed",
      metadata: {},
      most_expensive_turn: turn,
      most_rounds_turn: turn
    )
    turn_diagnostics_snapshot = TurnDiagnosticsSnapshot.create!(
      installation: context[:installation],
      conversation: conversation,
      turn: turn,
      lifecycle_state: "completed",
      metadata: {}
    )
    supervision_rows = create_supervision_rows!(context:, conversation:, turn:)
    export_request = create_export_request!(request_kind: "conversation_export", context: context, conversation: conversation)
    debug_export_request = create_export_request!(request_kind: "debug_export", context: context, conversation: conversation)

    plan = Conversations::PurgePlan.new(conversation: conversation)

    assert plan.remaining_owned_rows?

    assert_difference("ConversationDiagnosticsSnapshot.count", -1) do
      assert_difference("TurnDiagnosticsSnapshot.count", -1) do
        assert_difference("ConversationSupervisionSession.count", -1) do
          assert_difference("ConversationSupervisionSnapshot.count", -1) do
              assert_difference("ConversationSupervisionMessage.count", -1) do
                assert_difference("ConversationSupervisionState.count", -1) do
                  assert_difference("ConversationCapabilityGrant.count", -1) do
                    assert_difference("ConversationControlRequest.count", -1) do
                      assert_difference("ConversationExportRequest.count", -2) do
                        assert_difference("ActiveStorage::Attachment.count", -2) do
                          plan.execute!
                        end
                      end
                    end
                  end
              end
            end
          end
        end
      end
    end

    assert_not plan.remaining_owned_rows?
    assert_not ConversationDiagnosticsSnapshot.exists?(conversation_diagnostics_snapshot.id)
    assert_not TurnDiagnosticsSnapshot.exists?(turn_diagnostics_snapshot.id)
    assert_not ConversationSupervisionSession.exists?(supervision_rows.fetch(:session).id)
    assert_not ConversationSupervisionSnapshot.exists?(supervision_rows.fetch(:snapshot).id)
    assert_not ConversationSupervisionMessage.exists?(supervision_rows.fetch(:message).id)
    assert_not ConversationSupervisionState.exists?(supervision_rows.fetch(:state).id)
    assert_not ConversationCapabilityGrant.exists?(supervision_rows.fetch(:grant).id)
    assert_not ConversationControlRequest.exists?(supervision_rows.fetch(:control_request).id)
    assert_not ConversationExportRequest.exists?(export_request.id)
    assert_not ConversationExportRequest.exists?(debug_export_request.id)
  end

  test "purges derived rows without query explosion" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Derived query budget input",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    workflow_run = create_workflow_run!(turn: turn)
    create_workflow_node!(workflow_run: workflow_run)
    attach_selected_output!(turn, content: "Derived query budget output")

    ConversationDiagnosticsSnapshot.create!(
      installation: context[:installation],
      conversation: conversation,
      lifecycle_state: "completed",
      metadata: {},
      most_expensive_turn: turn,
      most_rounds_turn: turn
    )
    TurnDiagnosticsSnapshot.create!(
      installation: context[:installation],
      conversation: conversation,
      turn: turn,
      lifecycle_state: "completed",
      metadata: {}
    )
    create_supervision_rows!(context:, conversation:, turn:)
    create_export_request!(request_kind: "conversation_export", context: context, conversation: conversation)
    create_export_request!(request_kind: "debug_export", context: context, conversation: conversation)

    queries = capture_sql_queries do
      Conversations::PurgePlan.new(conversation: conversation).execute!
    end

    assert_operator queries.length, :<=, 65, "Expected purge plan execution to stay under 65 SQL queries, got #{queries.length}:\n#{queries.join("\n")}"
  end

  private

  def create_export_request!(request_kind:, context:, conversation:)
    request = ConversationExportRequest.create!(
      installation: context[:installation],
      workspace: context[:workspace],
      conversation: conversation,
      user: context[:user],
      request_kind: request_kind,
      lifecycle_state: "queued",
      expires_at: 2.hours.from_now,
      request_payload: {
        "bundle_kind" => request_kind == "debug_export" ? "conversation_debug_export" : "conversation_export",
      }
    )
    request.bundle_file.attach(
      io: StringIO.new("#{request_kind} bundle"),
      filename: "#{request_kind}-#{next_test_sequence}.zip",
      content_type: "application/zip"
    )
    request.update!(
      lifecycle_state: "succeeded",
      started_at: Time.current,
      finished_at: Time.current,
      result_payload: {
        "bundle_kind" => request_kind == "debug_export" ? "conversation_debug_export" : "conversation_export",
      }
    )
    request
  end

  def create_supervision_rows!(context:, conversation:, turn:)
    session = ConversationSupervisionSession.create!(
      installation: context[:installation],
      target_conversation: conversation,
      user: conversation.user,
      workspace: conversation.workspace,
      agent: conversation.agent,
      initiator: context[:user],
      lifecycle_state: "open",
      responder_strategy: "builtin",
      capability_policy_snapshot: {},
      last_snapshot_at: Time.current
    )
    assert_includes Conversation.attribute_names, "supervision_enabled"
    assert_includes Conversation.attribute_names, "detailed_progress_enabled"
    assert_includes Conversation.attribute_names, "side_chat_enabled"
    assert_includes Conversation.attribute_names, "control_enabled"
    conversation.update!(
      supervision_enabled: true,
      detailed_progress_enabled: true,
      side_chat_enabled: true,
      control_enabled: true
    )
    state = ConversationSupervisionState.create!(
      installation: context[:installation],
      target_conversation: conversation,
      user: conversation.user,
      workspace: conversation.workspace,
      agent: conversation.agent,
      overall_state: "running",
      current_owner_kind: "workflow_run",
      current_owner_public_id: "workflow_run_public_id",
      last_progress_at: Time.current,
      status_payload: {}
    )
    snapshot = ConversationSupervisionSnapshot.create!(
      installation: context[:installation],
      target_conversation: conversation,
      conversation_supervision_session: session,
      user: conversation.user,
      workspace: conversation.workspace,
      agent: conversation.agent,
      conversation_supervision_state_public_id: state.public_id,
      anchor_turn_public_id: turn.public_id,
      anchor_turn_sequence_snapshot: turn.sequence,
      conversation_event_projection_sequence_snapshot: 1,
      active_subagent_connection_public_ids: [],
      bundle_payload: {},
      machine_status_payload: {}
    )
    message = ConversationSupervisionMessage.create!(
      installation: context[:installation],
      target_conversation: conversation,
      conversation_supervision_session: session,
      conversation_supervision_snapshot: snapshot,
      user: conversation.user,
      workspace: conversation.workspace,
      agent: conversation.agent,
      role: "user",
      content: "What are you doing?"
    )
    grant = ConversationCapabilityGrant.create!(
      installation: context[:installation],
      target_conversation: conversation,
      grantee_kind: "user",
      grantee_public_id: context[:user].public_id,
      capability: "request_turn_interrupt",
      grant_state: "active",
      policy_payload: {}
    )
    control_request = ConversationControlRequest.create!(
      installation: context[:installation],
      conversation_supervision_session: session,
      target_conversation: conversation,
      user: conversation.user,
      workspace: conversation.workspace,
      agent: conversation.agent,
      request_kind: "request_status_refresh",
      target_kind: "conversation",
      target_public_id: conversation.public_id,
      lifecycle_state: "queued",
      request_payload: {},
      result_payload: {}
    )

    {
      session: session,
      snapshot: snapshot,
      message: message,
      state: state,
      grant: grant,
      control_request: control_request,
    }
  end
end
