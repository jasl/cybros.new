require "test_helper"

class Workflows::ContextAssemblerTest < ActiveSupport::TestCase
  test "assembles context from visible transcript messages imports and capability-gated attachment projections" do
    context = prepare_workflow_execution_context!(create_workspace_context!)
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    previous_turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Earlier input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    previous_output = attach_selected_output!(previous_turn, content: "Earlier output")
    unsupported_audio = create_message_attachment!(
      message: previous_output,
      filename: "call.mp3",
      content_type: "audio/mpeg",
      body: "audio-bytes",
      identify: false
    )
    excluded_turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Excluded input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    excluded_attachment = create_message_attachment!(
      message: excluded_turn.selected_input_message,
      filename: "secret.txt",
      content_type: "text/plain",
      body: "secret"
    )
    Messages::UpdateVisibility.call(
      conversation: conversation,
      message: excluded_turn.selected_input_message,
      excluded_from_context: true
    )
    summary_segment = ConversationSummaries::CreateSegment.call(
      conversation: conversation,
      start_message: previous_turn.selected_input_message,
      end_message: previous_output,
      content: "Earlier summary"
    )
    Conversations::AddImport.call(
      conversation: conversation,
      kind: "quoted_context",
      summary_segment: summary_segment
    )
    current_turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Current input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: { "temperature" => 0.2 },
      resolved_model_selection_snapshot: {}
    )
    supported_file = create_message_attachment!(
      message: current_turn.selected_input_message,
      filename: "brief.pdf",
      content_type: "application/pdf",
      body: "pdf-bytes"
    )
    current_turn.update!(
      resolved_model_selection_snapshot: Workflows::ResolveModelSelector.call(
        turn: current_turn,
        selector_source: "conversation"
      )
    )

    snapshot = Workflows::ContextAssembler.call(turn: current_turn)

    assert_equal({ "temperature" => 0.2 }, snapshot["config"])
    assert_equal context[:user].public_id, snapshot.dig("execution_context", "identity", "user_id")
    assert_equal context[:workspace].public_id, snapshot.dig("execution_context", "identity", "workspace_id")
    assert_equal conversation.public_id, snapshot.dig("execution_context", "identity", "conversation_id")
    assert_equal current_turn.public_id, snapshot.dig("execution_context", "identity", "turn_id")
    assert_equal context[:agent_deployment].public_id, snapshot.dig("execution_context", "identity", "agent_deployment_id")
    assert_equal(
      [
        previous_turn.selected_input_message.public_id,
        previous_output.public_id,
        current_turn.selected_input_message.public_id,
      ],
      snapshot.dig("execution_context", "context_messages").map { |message| message.fetch("message_id") }
    )
    assert_equal ["quoted_context"], snapshot.dig("execution_context", "context_imports").map { |item| item.fetch("kind") }
    expected_attachment_ids = [unsupported_audio.public_id, supported_file.public_id].sort

    assert_equal expected_attachment_ids, snapshot.dig("execution_context", "attachment_manifest").map { |item| item.fetch("attachment_id") }.sort
    assert_equal expected_attachment_ids, snapshot.dig("execution_context", "runtime_attachment_manifest").map { |item| item.fetch("attachment_id") }.sort
    assert_equal [supported_file.public_id], snapshot.dig("execution_context", "model_input_attachments").map { |item| item.fetch("attachment_id") }
    assert_equal [unsupported_audio.public_id], snapshot.dig("execution_context", "attachment_diagnostics").map { |item| item.fetch("attachment_id") }
    assert_equal "unsupported_modality", snapshot.dig("execution_context", "attachment_diagnostics").first.fetch("reason")
    refute_includes snapshot.dig("execution_context", "attachment_manifest").map { |item| item.fetch("attachment_id") }, excluded_attachment.public_id
  end

  test "assembles automation turns without requiring a transcript-bearing input message" do
    context = prepare_workflow_execution_context!(create_workspace_context!)
    conversation = Conversations::CreateAutomationRoot.call(workspace: context[:workspace])
    turn = Turns::StartAutomationTurn.call(
      conversation: conversation,
      origin_kind: "automation_schedule",
      origin_payload: { "cron" => "0 9 * * *" },
      source_ref_type: "AutomationSchedule",
      source_ref_id: "schedule-1",
      idempotency_key: "idemp-1",
      external_event_key: "evt-1",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: { "temperature" => 0.1 },
      resolved_model_selection_snapshot: {}
    )
    turn.update!(
      resolved_model_selection_snapshot: Workflows::ResolveModelSelector.call(
        turn: turn,
        selector_source: "conversation"
      )
    )

    snapshot = Workflows::ContextAssembler.call(turn: turn)

    assert_equal({ "temperature" => 0.1 }, snapshot["config"])
    assert_equal [], snapshot.dig("execution_context", "context_messages")
    assert_equal "automation_schedule", snapshot.dig("execution_context", "turn_origin", "origin_kind")
    assert_equal({ "cron" => "0 9 * * *" }, snapshot.dig("execution_context", "turn_origin", "origin_payload"))
    assert_equal context[:workspace].public_id, snapshot.dig("execution_context", "identity", "workspace_id")
  end
end
