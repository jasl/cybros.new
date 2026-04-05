require "test_helper"

class Conversations::PurgePlanTest < ActiveSupport::TestCase
  test "removes owned rows so remaining_owned_rows? flips false after execute" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_program_version: context[:agent_program_version]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Purge plan input",
      agent_program_version: context[:agent_program_version],
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

  test "removes derived diagnostics, observation, and export rows before the conversation is deleted" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_program_version: context[:agent_program_version]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Derived cleanup input",
      agent_program_version: context[:agent_program_version],
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
    observation_session = ConversationObservationSession.create!(
      installation: context[:installation],
      target_conversation: conversation,
      initiator: context[:user],
      lifecycle_state: "open",
      responder_strategy: "builtin",
      capability_policy_snapshot: {}
    )
    observation_frame = ConversationObservationFrame.create!(
      installation: context[:installation],
      target_conversation: conversation,
      conversation_observation_session: observation_session,
      anchor_turn_public_id: turn.public_id,
      anchor_turn_sequence_snapshot: turn.sequence,
      conversation_event_projection_sequence_snapshot: 1,
      wait_state: "ready",
      active_subagent_session_public_ids: [],
      bundle_snapshot: {},
      assessment_payload: {}
    )
    observation_message = ConversationObservationMessage.create!(
      installation: context[:installation],
      target_conversation: conversation,
      conversation_observation_session: observation_session,
      conversation_observation_frame: observation_frame,
      role: "user",
      content: "What are you doing?"
    )
    export_request = create_export_request!(klass: ConversationExportRequest, context: context, conversation: conversation)
    debug_export_request = create_export_request!(klass: ConversationDebugExportRequest, context: context, conversation: conversation)

    plan = Conversations::PurgePlan.new(conversation: conversation)

    assert plan.remaining_owned_rows?

    assert_difference("ConversationDiagnosticsSnapshot.count", -1) do
      assert_difference("TurnDiagnosticsSnapshot.count", -1) do
        assert_difference("ConversationObservationSession.count", -1) do
          assert_difference("ConversationObservationFrame.count", -1) do
            assert_difference("ConversationObservationMessage.count", -1) do
              assert_difference("ConversationExportRequest.count", -1) do
                assert_difference("ConversationDebugExportRequest.count", -1) do
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

    assert_not plan.remaining_owned_rows?
    assert_not ConversationDiagnosticsSnapshot.exists?(conversation_diagnostics_snapshot.id)
    assert_not TurnDiagnosticsSnapshot.exists?(turn_diagnostics_snapshot.id)
    assert_not ConversationObservationSession.exists?(observation_session.id)
    assert_not ConversationObservationFrame.exists?(observation_frame.id)
    assert_not ConversationObservationMessage.exists?(observation_message.id)
    assert_not ConversationExportRequest.exists?(export_request.id)
    assert_not ConversationDebugExportRequest.exists?(debug_export_request.id)
  end

  private

  def create_export_request!(klass:, context:, conversation:)
    request = klass.create!(
      installation: context[:installation],
      workspace: context[:workspace],
      conversation: conversation,
      user: context[:user],
      lifecycle_state: "queued",
      expires_at: 2.hours.from_now,
      request_payload: { "bundle_kind" => klass.name }
    )
    request.bundle_file.attach(
      io: StringIO.new("#{klass.name} bundle"),
      filename: "#{klass.model_name.singular}-#{next_test_sequence}.zip",
      content_type: "application/zip"
    )
    request.update!(
      lifecycle_state: "succeeded",
      started_at: Time.current,
      finished_at: Time.current,
      result_payload: { "bundle_kind" => klass.name }
    )
    request
  end
end
