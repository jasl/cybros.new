require "test_helper"

class ConversationDebugExportsBuildPayloadTest < ActiveSupport::TestCase
  include ConversationSupervisionFixtureBuilder

  setup do
    truncate_all_tables!
  end

  test "builds a debug payload with diagnostics workflow traces and usage data" do
    fixture = build_debug_export_fixture!
    conversation = fixture.fetch(:conversation)
    subagent_connection = fixture.fetch(:subagent_connection)

    payload = ConversationDebugExports::BuildPayload.call(conversation: conversation)

    assert_equal "conversation_debug_export", payload.fetch("bundle_kind")
    assert_equal "2026-04-16", payload.fetch("bundle_version")
    assert_equal conversation.public_id, payload.dig("conversation_payload", "conversation", "public_id")
    assert_equal conversation.public_id, payload.dig("diagnostics", "conversation", "conversation_id")
    assert_equal 1, payload.fetch("workflow_runs").length
    assert_equal %w[provider_round_1 debug_intent_1], payload.fetch("workflow_nodes").map { |node| node.fetch("node_key") }
    assert_equal 1, payload.fetch("workflow_edges").length
    assert_equal "provider_round_1", payload.fetch("workflow_edges").first.fetch("from_node_key")
    assert_equal "debug_intent_1", payload.fetch("workflow_edges").first.fetch("to_node_key")
    intent_node_payload = payload.fetch("workflow_nodes").find { |node| node.fetch("node_key") == "debug_intent_1" }
    assert_equal "batch-debug-1", intent_node_payload.fetch("intent_batch_id")
    assert_equal({ "summary" => "debug intent" }, intent_node_payload.fetch("intent_payload"))
    assert_equal subagent_connection.public_id, intent_node_payload.fetch("spawned_subagent_connection_id")
    assert_equal "provider_rate_limited", intent_node_payload.fetch("blocked_retry_failure_kind")
    assert_equal 2, intent_node_payload.fetch("blocked_retry_attempt_no")
    barrier_artifact = payload.fetch("workflow_artifacts").find { |artifact| artifact.fetch("artifact_kind") == "intent_batch_barrier" }
    assert_equal "provider_round_1", barrier_artifact.fetch("workflow_node_key")
    assert_equal "wait_all", barrier_artifact.fetch("barrier_kind")
    assert_equal "serial", barrier_artifact.fetch("dispatch_mode")
    round_node_payload = payload.fetch("workflow_nodes").find { |node| node.fetch("node_key") == "provider_round_1" }
    assert_equal 1, round_node_payload.fetch("provider_round_index")
    assert_equal true, round_node_payload.fetch("transcript_side_effect_committed")
    assert_equal 1, payload.fetch("workflow_node_events").length
    assert_equal subagent_connection.public_id, payload.fetch("subagent_connections").first.fetch("subagent_connection_id")
    assert_equal "specialist", payload.fetch("subagent_connections").first.fetch("profile_group")
    assert_equal "researcher", payload.fetch("subagent_connections").first.fetch("specialist_key")
    assert_equal "role:researcher", payload.fetch("subagent_connections").first.fetch("resolved_model_selector_hint")
    assert_not payload.fetch("subagent_connections").first.key?("summary")
    assert_equal(
      fixture.fetch(:context).fetch(:agent_definition_version).public_id,
      payload.fetch("agent_task_runs").first.fetch("holder_agent_definition_version_id")
    )
    refute payload.fetch("agent_task_runs").first.key?("holder_agent_snapshot_id")
    assert_equal 120, payload.fetch("usage_events").first.fetch("input_tokens")
    assert_equal(
      fixture.fetch(:context).fetch(:agent_definition_version).public_id,
      payload.fetch("usage_events").first.fetch("agent_definition_version_id")
    )
    refute payload.fetch("usage_events").first.key?("agent_snapshot_id")
    assert_equal "available", payload.fetch("usage_events").first.fetch("prompt_cache_status")
    assert_equal 60, payload.fetch("usage_events").first.fetch("cached_input_tokens")
    assert_equal 60, payload.dig("diagnostics", "conversation", "cached_input_tokens_total")
    assert_equal 1, payload.dig("diagnostics", "conversation", "prompt_cache_available_event_count")
    assert_equal 0.5, payload.dig("diagnostics", "conversation", "prompt_cache_hit_rate")
    assert_equal 60, payload.dig("diagnostics", "turns", 0, "cached_input_tokens_total")
    assert_equal 1, payload.dig("diagnostics", "turns", 0, "prompt_cache_available_event_count")
    assert_equal 0.5, payload.dig("diagnostics", "turns", 0, "prompt_cache_hit_rate")
    refute_includes JSON.generate(payload), %("#{conversation.id}")
    refute_includes JSON.generate(payload), %("#{fixture.fetch(:turn).id}")
  end

  test "preloads normalized associations instead of repeatedly reloading workflow projections" do
    fixture = build_debug_export_fixture!

    queries = capture_sql_queries do
      ConversationDebugExports::BuildPayload.call(conversation: fixture.fetch(:conversation))
    end

    assert_operator queries.length, :<=, 120, "Expected debug export payload to stay under 120 SQL queries, got #{queries.length}:\n#{queries.join("\n")}"
  end

  test "recomputes diagnostics before serializing when stored snapshots are stale" do
    fixture = build_debug_export_fixture!
    conversation = fixture.fetch(:conversation)
    turn = fixture.fetch(:turn)
    context = fixture.fetch(:context)

    ConversationDiagnostics::RecomputeConversationSnapshot.call(conversation: conversation)

    UsageEvent.create!(
      installation: context[:installation],
      conversation_id: conversation.id,
      turn_id: turn.id,
      user: context[:user],
      workspace: context[:workspace],
      agent: context[:agent_definition_version].agent,
      agent_definition_version: context[:agent_definition_version],
      provider_handle: "openrouter",
      model_ref: "openai-gpt-5.4",
      operation_kind: "text_generation",
      success: true,
      input_tokens: 30,
      output_tokens: 10,
      prompt_cache_status: "unknown",
      latency_ms: 600,
      occurred_at: Time.current + 1.minute
    )

    payload = ConversationDebugExports::BuildPayload.call(conversation: conversation)

    assert_equal 2, payload.dig("diagnostics", "conversation", "usage_event_count")
    assert_equal 150, payload.dig("diagnostics", "conversation", "input_tokens_total")
    assert_equal 55, payload.dig("diagnostics", "conversation", "output_tokens_total")
    assert_equal 1, payload.fetch("diagnostics").fetch("turns").length
    assert_equal 2, payload.dig("diagnostics", "turns", 0, "usage_event_count")
    assert_equal 150, payload.dig("diagnostics", "turns", 0, "input_tokens_total")
    assert_equal 55, payload.dig("diagnostics", "turns", 0, "output_tokens_total")
  end

  test "includes supervision sessions and transcript messages in the debug payload" do
    fixture = prepare_conversation_supervision_context!
    session = create_conversation_supervision_session!(fixture)
    result = EmbeddedAgents::ConversationSupervision::AppendMessage.call(
      actor: fixture.fetch(:user),
      conversation_supervision_session: session,
      content: "What changed most recently?"
    )

    payload = ConversationDebugExports::BuildPayload.call(conversation: fixture.fetch(:conversation))

    assert_equal 1, payload.fetch("conversation_supervision_sessions").length
    assert_equal session.public_id, payload.fetch("conversation_supervision_sessions").first.fetch("supervision_session_id")
    assert_equal 2, payload.fetch("conversation_supervision_messages").length
    assert_equal %w[user supervisor_agent], payload.fetch("conversation_supervision_messages").map { |message| message.fetch("role") }
    assert_equal result.dig("human_sidechat", "content"), payload.fetch("conversation_supervision_messages").last.fetch("content")
    assert_equal "mutable", payload.dig("conversation_payload", "conversation", "interaction_lock_state")
    assert_equal default_interactive_entry_policy_payload, payload.dig("conversation_payload", "conversation", "entry_policy_payload")
    refute payload.dig("conversation_payload", "conversation").key?("addressability")
    refute_includes JSON.generate(payload), %("#{session.id}")
  end

  private

  def build_debug_export_fixture!
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Debug input",
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
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version],
      kind: "fork",
      entry_policy_payload: agent_internal_entry_policy_payload
    )
    subagent_connection = SubagentConnection.create!(
      installation: context[:installation],
      owner_conversation: conversation,
      conversation: child_conversation,
      user: child_conversation.user,
      workspace: child_conversation.workspace,
      agent: child_conversation.agent,
      origin_turn: turn,
      scope: "turn",
      profile_key: "researcher",
      resolved_model_selector_hint: "role:researcher",
      depth: 0
    )
    yielding_node = create_workflow_node!(
      workflow_run: workflow_run,
      node_key: "provider_round_1",
      node_type: "provider_round",
      provider_round_index: 1,
      transcript_side_effect_committed: true,
      lifecycle_state: "completed",
      started_at: 2.minutes.ago,
      finished_at: 90.seconds.ago,
      presentation_policy: "ops_trackable"
    )
    intent_node = create_workflow_node!(
      workflow_run: workflow_run,
      node_key: "debug_intent_1",
      node_type: "ops_annotation",
      intent_kind: "ops_annotation",
      intent_batch_id: "batch-debug-1",
      intent_id: "intent-debug-1",
      intent_requirement: "required",
      intent_conflict_scope: "debug",
      intent_idempotency_key: "intent-debug-1",
      yielding_workflow_node: yielding_node,
      spawned_subagent_connection: subagent_connection,
      blocked_retry_failure_kind: "provider_rate_limited",
      blocked_retry_attempt_no: 2,
      lifecycle_state: "completed",
      started_at: 80.seconds.ago,
      finished_at: 70.seconds.ago,
      presentation_policy: "ops_trackable"
    )
    create_workflow_edge!(
      workflow_run: workflow_run,
      from_node: yielding_node,
      to_node: intent_node,
      ordinal: 0
    )
    WorkflowArtifact.create!(
      installation: context[:installation],
      workflow_run: workflow_run,
      workflow_node: yielding_node,
      artifact_key: "batch-debug-1",
      artifact_kind: "intent_batch_manifest",
      storage_mode: "json_document",
      payload: {
        "batch_id" => "batch-debug-1",
        "stages" => [
          {
            "stage_index" => 0,
            "dispatch_mode" => "serial",
            "completion_barrier" => "none",
            "intents" => [
              {
                "intent_id" => "intent-debug-1",
                "intent_kind" => "ops_annotation",
                "payload" => { "summary" => "debug intent" },
              },
            ],
          },
        ],
      }
    )
    WorkflowArtifact.create!(
      installation: context[:installation],
      workflow_run: workflow_run,
      workflow_node: yielding_node,
      artifact_key: "batch-debug-1:stage:0",
      artifact_kind: "intent_batch_barrier",
      storage_mode: "json_document",
      payload: {
        "stage" => {
          "stage_index" => 0,
          "dispatch_mode" => "serial",
          "completion_barrier" => "wait_all",
        },
      }
    )
    WorkflowNodeEvent.create!(
      installation: context[:installation],
      workflow_run: workflow_run,
      workflow_node: yielding_node,
      event_kind: "started",
      ordinal: 0,
      payload: { "state" => "started" }
    )
    create_agent_task_run!(
      workflow_node: yielding_node,
      workflow_run: workflow_run,
      conversation: conversation,
      turn: turn,
      agent: context[:agent_definition_version].agent,
      lifecycle_state: "completed",
      started_at: 70.seconds.ago,
      finished_at: 60.seconds.ago,
      holder_agent_connection: context[:agent_connection]
    )
    UsageEvent.create!(
      installation: context[:installation],
      conversation_id: conversation.id,
      turn_id: turn.id,
      user: context[:user],
      workspace: context[:workspace],
      agent: context[:agent_definition_version].agent,
      agent_definition_version: context[:agent_definition_version],
      provider_handle: "openrouter",
      model_ref: "openai-gpt-5.4",
      operation_kind: "text_generation",
      success: true,
      input_tokens: 120,
      output_tokens: 45,
      prompt_cache_status: "available",
      cached_input_tokens: 60,
      latency_ms: 800,
      occurred_at: Time.current
    )

    {
      context: context,
      conversation: conversation,
      turn: turn,
      workflow_run: workflow_run,
      subagent_connection: subagent_connection,
    }
  end
end
