require "test_helper"

class ConversationDebugExportsBuildPayloadTest < ActiveSupport::TestCase
  test "builds a debug payload with diagnostics workflow traces and usage data" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Debug input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    source_attachment = create_message_attachment!(
      message: turn.selected_input_message,
      filename: "input.txt",
      body: "debug attachment"
    )
    output_message = attach_selected_output!(turn, content: "Debug output")
    create_message_attachment!(
      message: output_message,
      origin_attachment: source_attachment,
      filename: "output.txt",
      body: "derived attachment"
    )
    workflow_run = create_workflow_run!(
      turn: turn,
      lifecycle_state: "completed"
    )
    child_conversation = create_conversation_record!(
      workspace: context[:workspace],
      parent_conversation: conversation,
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment],
      kind: "fork",
      addressability: "agent_addressable"
    )
    subagent_session = SubagentSession.create!(
      installation: context[:installation],
      owner_conversation: conversation,
      conversation: child_conversation,
      origin_turn: turn,
      scope: "turn",
      profile_key: "worker",
      depth: 0
    )
    workflow_node = create_workflow_node!(
      workflow_run: workflow_run,
      node_key: "provider_round_1",
      node_type: "provider_round",
      lifecycle_state: "completed",
      started_at: 2.minutes.ago,
      finished_at: 90.seconds.ago,
      presentation_policy: "ops_trackable"
    )
    WorkflowNodeEvent.create!(
      installation: context[:installation],
      workflow_run: workflow_run,
      workflow_node: workflow_node,
      event_kind: "started",
      ordinal: 0,
      payload: { "state" => "started" }
    )
    UsageEvent.create!(
      installation: context[:installation],
      conversation_id: conversation.id,
      turn_id: turn.id,
      user: context[:user],
      workspace: context[:workspace],
      agent_installation: context[:agent_deployment].agent_installation,
      agent_deployment: context[:agent_deployment],
      provider_handle: "openrouter",
      model_ref: "openai-gpt-5.4",
      operation_kind: "text_generation",
      success: true,
      input_tokens: 123,
      output_tokens: 45,
      latency_ms: 800,
      occurred_at: Time.current
    )

    payload = ConversationDebugExports::BuildPayload.call(conversation: conversation)

    assert_equal "conversation_debug_export", payload.fetch("bundle_kind")
    assert_equal "2026-04-02", payload.fetch("bundle_version")
    assert_equal conversation.public_id, payload.dig("conversation_payload", "conversation", "public_id")
    assert_equal conversation.public_id, payload.dig("diagnostics", "conversation", "conversation_id")
    assert_equal 1, payload.fetch("workflow_runs").length
    assert_equal "provider_round_1", payload.fetch("workflow_nodes").first.fetch("node_key")
    assert_equal 1, payload.fetch("workflow_node_events").length
    assert_equal subagent_session.public_id, payload.fetch("subagent_sessions").first.fetch("subagent_session_id")
    assert_not payload.fetch("subagent_sessions").first.key?("summary")
    assert_equal 123, payload.fetch("usage_events").first.fetch("input_tokens")
    refute_includes JSON.generate(payload), %("#{conversation.id}")
    refute_includes JSON.generate(payload), %("#{turn.id}")
  end
end
