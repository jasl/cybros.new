require "test_helper"

class Workflows::BuildExecutionSnapshotTest < ActiveSupport::TestCase
  test "builds an execution snapshot from visible transcript messages imports and capability-gated attachment projections" do
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
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

    snapshot = build_execution_snapshot_for!(turn: current_turn)

    refute snapshot.to_h.key?("execution_context")
    assert_equal context[:user].public_id, snapshot.identity.fetch("user_id")
    assert_equal context[:workspace].public_id, snapshot.identity.fetch("workspace_id")
    assert_equal conversation.public_id, snapshot.identity.fetch("conversation_id")
    assert_equal current_turn.public_id, snapshot.identity.fetch("turn_id")
    assert_equal context[:execution_environment].public_id, snapshot.identity.fetch("execution_environment_id")
    assert_equal context[:agent_deployment].public_id, snapshot.identity.fetch("agent_deployment_id")
    assert_equal "codex_subscription", snapshot.model_context.fetch("provider_handle")
    assert_equal "gpt-5.4", snapshot.model_context.fetch("model_ref")
    assert_equal "gpt-5.4", snapshot.model_context.fetch("api_model")
    assert_equal "responses", snapshot.provider_execution.fetch("wire_api")
    assert_equal "high", snapshot.provider_execution.fetch("execution_settings").fetch("reasoning_effort")
    assert_equal 1_000_000, snapshot.budget_hints.fetch("hard_limits").fetch("context_window_tokens")
    assert_equal 128_000, snapshot.budget_hints.fetch("hard_limits").fetch("max_output_tokens")
    assert_equal 900_000, snapshot.budget_hints.fetch("advisory_hints").fetch("recommended_compaction_threshold")
    assert_equal "User", snapshot.turn_origin.fetch("source_ref_type")
    assert_equal context[:user].public_id, snapshot.turn_origin.fetch("source_ref_id")
    assert_equal(
      [
        previous_turn.selected_input_message.public_id,
        previous_output.public_id,
        current_turn.selected_input_message.public_id,
      ],
      snapshot.context_messages.map { |message| message.fetch("message_id") }
    )
    assert_equal ["quoted_context"], snapshot.context_imports.map { |item| item.fetch("kind") }
    expected_attachment_ids = [unsupported_audio.public_id, supported_file.public_id].sort

    assert_equal expected_attachment_ids, snapshot.attachment_manifest.map { |item| item.fetch("attachment_id") }.sort
    assert_equal expected_attachment_ids, snapshot.runtime_attachment_manifest.map { |item| item.fetch("attachment_id") }.sort
    assert_equal [supported_file.public_id], snapshot.model_input_attachments.map { |item| item.fetch("attachment_id") }
    assert_equal [unsupported_audio.public_id], snapshot.attachment_diagnostics.map { |item| item.fetch("attachment_id") }
    assert_equal "unsupported_modality", snapshot.attachment_diagnostics.first.fetch("reason")
    refute_includes snapshot.attachment_manifest.map { |item| item.fetch("attachment_id") }, excluded_attachment.public_id
  end

  test "builds automation turns without requiring a transcript-bearing input message" do
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    conversation = Conversations::CreateAutomationRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
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

    snapshot = build_execution_snapshot_for!(turn: turn)

    assert_equal [], snapshot.context_messages
    assert_equal "automation_schedule", snapshot.turn_origin.fetch("origin_kind")
    assert_equal({ "cron" => "0 9 * * *" }, snapshot.turn_origin.fetch("origin_payload"))
    assert_equal context[:workspace].public_id, snapshot.identity.fetch("workspace_id")
    assert_equal "codex_subscription", snapshot.model_context.fetch("provider_handle")
    assert_equal "responses", snapshot.provider_execution.fetch("wire_api")
  end

  test "omits attachments when the environment disables conversation uploads" do
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    context[:execution_environment].update!(
      capability_payload: { "conversation_attachment_upload" => false }
    )
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Attachment-disabled input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    attachment = create_message_attachment!(
      message: turn.selected_input_message,
      filename: "brief.pdf",
      content_type: "application/pdf",
      body: "brief"
    )

    snapshot = build_execution_snapshot_for!(turn: turn)

    assert_equal [], snapshot.attachment_manifest
    assert_equal [], snapshot.runtime_attachment_manifest
    assert_equal [], snapshot.model_input_attachments
    assert_equal [attachment.public_id], snapshot.attachment_diagnostics.map { |item| item.fetch("attachment_id") }
    assert_equal "conversation_attachment_upload_disabled", snapshot.attachment_diagnostics.first.fetch("reason")
  end
end
