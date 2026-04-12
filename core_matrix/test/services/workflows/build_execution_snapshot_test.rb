require "test_helper"

class Workflows::BuildExecutionSnapshotTest < ActiveSupport::TestCase
  test "builds an execution snapshot from visible transcript messages imports and canonical attachments" do
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    previous_turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Earlier input",
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

    assert_equal context[:user].public_id, snapshot.identity.fetch("user_id")
    assert_equal context[:workspace].public_id, snapshot.identity.fetch("workspace_id")
    assert_equal conversation.public_id, snapshot.identity.fetch("conversation_id")
    assert_equal current_turn.public_id, snapshot.identity.fetch("turn_id")
    assert_equal context[:execution_runtime].public_id, snapshot.identity.fetch("execution_runtime_id")
    assert_equal context[:agent_definition_version].public_id, snapshot.identity.fetch("agent_definition_version_id")
    assert_equal "codex_subscription", snapshot.model_context.fetch("provider_handle")
    assert_equal "gpt-5.4", snapshot.model_context.fetch("model_ref")
    assert_equal "gpt-5.4", snapshot.model_context.fetch("api_model")
    assert_equal "responses", snapshot.provider_execution.fetch("wire_api")
    assert_equal(
      {
        "max_rounds" => 64,
        "parallel_tool_calls" => false,
        "max_parallel_tool_calls" => 1,
        "loop_detection" => {
          "enabled" => false,
        },
      },
      snapshot.provider_execution.fetch("loop_policy")
    )
    assert_equal(
      ProviderRequestSettingsSchema.for("responses").merge_execution_settings(
        request_defaults: test_provider_catalog_definition
          .dig(:providers, :codex_subscription, :models, "gpt-5.4", :request_defaults),
        runtime_overrides: current_turn.resolved_config_snapshot
      ),
      snapshot.provider_execution.fetch("execution_settings")
    )
    assert_equal 1_000_000, snapshot.budget_hints.fetch("hard_limits").fetch("context_window_tokens")
    assert_equal 128_000, snapshot.budget_hints.fetch("hard_limits").fetch("max_output_tokens")
    assert_equal 900_000, snapshot.budget_hints.fetch("advisory_hints").fetch("recommended_compaction_threshold")
    assert_equal "User", snapshot.turn_origin.fetch("source_ref_type")
    assert_equal context[:user].public_id, snapshot.turn_origin.fetch("source_ref_id")
    assert_equal conversation.public_id, snapshot.task.fetch("conversation_id")
    assert_equal current_turn.public_id, snapshot.task.fetch("turn_id")
    assert_equal(
      [
        previous_turn.selected_input_message.public_id,
        previous_output.public_id,
        current_turn.selected_input_message.public_id,
      ],
      snapshot.conversation_projection.fetch("messages").map { |message| message.fetch("message_id") }
    )
    assert_equal ["quoted_context"], snapshot.conversation_projection.fetch("context_imports").map { |item| item.fetch("kind") }
    assert_equal conversation.public_id, snapshot.conversation_projection.fetch("context_imports").first.fetch("source_conversation_id")
    assert_equal "Earlier summary", snapshot.conversation_projection.fetch("context_imports").first.fetch("content")
    assert_equal "main", snapshot.capability_projection.fetch("profile_key")
    assert_equal false, snapshot.capability_projection.fetch("is_subagent")
    assert_equal(
      RuntimeCapabilities::ComposeForTurn.call(turn: current_turn).fetch("tool_catalog").map { |entry| entry.fetch("tool_name") },
      snapshot.capability_projection.fetch("tool_surface").map { |entry| entry.fetch("tool_name") }
    )

    expected_attachment_ids = [unsupported_audio.public_id, supported_file.public_id].sort

    assert_equal expected_attachment_ids, snapshot.attachment_manifest.map { |item| item.fetch("attachment_id") }.sort
    assert_equal [supported_file.public_id], snapshot.model_input_attachments.map { |item| item.fetch("attachment_id") }
    assert_equal [unsupported_audio.public_id], snapshot.attachment_diagnostics.map { |item| item.fetch("attachment_id") }
    assert_equal "unsupported_modality", snapshot.attachment_diagnostics.first.fetch("reason")
    refute_includes snapshot.attachment_manifest.map { |item| item.fetch("attachment_id") }, excluded_attachment.public_id
  end

  test "projects prior agent outputs as assistant messages for provider-facing transcript state" do
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    previous_turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Earlier input",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    attach_selected_output!(previous_turn, content: "Earlier output")
    current_turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Current input",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    snapshot = build_execution_snapshot_for!(turn: current_turn)

    assert_equal ["user", "assistant", "user"], snapshot.conversation_projection.fetch("messages").map { |message| message.fetch("role") }
  end

  test "builds automation turns without requiring a transcript-bearing input message" do
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    conversation = Conversations::CreateAutomationRoot.call(workspace: context[:workspace])
    turn = Turns::StartAutomationTurn.call(
      conversation: conversation,
      origin_kind: "automation_schedule",
      origin_payload: { "cron" => "0 9 * * *" },
      source_ref_type: "AutomationSchedule",
      source_ref_id: "schedule-1",
      idempotency_key: "idemp-1",
      external_event_key: "evt-1",
      resolved_config_snapshot: { "temperature" => 0.1 },
      resolved_model_selection_snapshot: {}
    )

    snapshot = build_execution_snapshot_for!(turn: turn)

    assert_equal [], snapshot.conversation_projection.fetch("messages")
    assert_equal "automation_schedule", snapshot.turn_origin.fetch("origin_kind")
    assert_equal({ "cron" => "0 9 * * *" }, snapshot.turn_origin.fetch("origin_payload"))
    assert_equal context[:workspace].public_id, snapshot.identity.fetch("workspace_id")
    assert_equal "codex_subscription", snapshot.model_context.fetch("provider_handle")
    assert_equal "responses", snapshot.provider_execution.fetch("wire_api")
    assert_equal "automation_schedule", snapshot.task.fetch("origin_kind")
  end

  test "keeps canonical attachments even when execution runtime does not advertise request_attachment access" do
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    restricted_runtime_version = create_execution_runtime_version!(
      installation: context[:installation],
      execution_runtime: context[:execution_runtime],
      capability_payload_document: create_json_document!(
        installation: context[:installation],
        document_kind: "runtime_capability_payload",
        payload: { "attachment_access" => { "request_attachment" => false } }
      ),
      tool_catalog_document: create_json_document!(
        installation: context[:installation],
        document_kind: "runtime_tool_catalog",
        payload: context[:execution_runtime].tool_catalog
      ),
      reflected_host_metadata_document: create_json_document!(
        installation: context[:installation],
        document_kind: "reflected_host_metadata",
        payload: context[:execution_runtime].current_execution_runtime_version&.reflected_host_metadata || {}
      )
    )
    context[:execution_runtime].update!(published_execution_runtime_version: restricted_runtime_version)
    context[:execution_runtime_connection].update!(execution_runtime_version: restricted_runtime_version)
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Attachment-disabled input",
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

    assert_equal [attachment.public_id], snapshot.attachment_manifest.map { |item| item.fetch("attachment_id") }
    assert_equal [attachment.public_id], snapshot.model_input_attachments.map { |item| item.fetch("attachment_id") }
    assert_equal [], snapshot.attachment_diagnostics
  end

  test "skips superseded summary imports while retaining direct source message imports" do
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    anchor_turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Anchor input",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    superseded_segment = ConversationSummaries::CreateSegment.call(
      conversation: conversation,
      start_message: anchor_turn.selected_input_message,
      end_message: anchor_turn.selected_input_message,
      content: "Superseded summary"
    )
    retained_segment = ConversationSummaries::CreateSegment.call(
      conversation: conversation,
      start_message: anchor_turn.selected_input_message,
      end_message: anchor_turn.selected_input_message,
      content: "Retained summary",
      supersedes: superseded_segment
    )
    Conversations::AddImport.call(
      conversation: conversation,
      kind: "quoted_context",
      summary_segment: superseded_segment
    )
    Conversations::AddImport.call(
      conversation: conversation,
      kind: "quoted_context",
      summary_segment: retained_segment
    )
    Conversations::AddImport.call(
      conversation: conversation,
      kind: "quoted_context",
      source_message: anchor_turn.selected_input_message
    )
    current_turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Current input",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    snapshot = build_execution_snapshot_for!(turn: current_turn)

    refute_includes snapshot.context_imports.map { |item| item.fetch("content") }, "Superseded summary"
    assert_includes snapshot.context_imports.map { |item| item.fetch("content") }, "Retained summary"

    direct_import = snapshot.context_imports.find do |item|
      item.fetch("source_message_id", nil) == anchor_turn.selected_input_message.public_id
    end

    assert_equal conversation.public_id, direct_import.fetch("source_conversation_id")
    assert_equal "Anchor input", direct_import.fetch("content")
  end

  test "filters provider execution settings through the shared schema for chat completions" do
    catalog_definition = test_provider_catalog_definition.deep_dup
    catalog_definition[:providers][:dev][:models]["mock-model"] = test_model_definition(
      display_name: "Mock Model",
      api_model: "mock-model",
      tokenizer_hint: "o200k_base",
      context_window_tokens: 100,
      max_output_tokens: 40,
      context_soft_limit_ratio: 0.5,
      request_defaults: {
        temperature: 0.9,
        top_p: 0.95,
        top_k: 20,
        min_p: 0.1,
        presence_penalty: 0.2,
        repetition_penalty: 1.1,
      }
    )
    catalog = build_test_provider_catalog_from(catalog_definition)
    workflow_run = nil

    with_stubbed_provider_catalog(catalog) do
      context = prepare_workflow_execution_setup!(create_workspace_context!)
      ProviderEntitlement.create!(
        installation: context[:installation],
        provider_handle: "dev",
        entitlement_key: "dev_window",
        window_kind: "rolling_five_hours",
        window_seconds: 5.hours.to_i,
        quota_limit: 200_000,
        active: true,
        metadata: {}
      )
      conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
      turn = Turns::StartUserTurn.call(
        conversation: conversation,
        content: "Current input",
        resolved_config_snapshot: {
          "temperature" => 0.4,
          "presence_penalty" => 0.6,
          "sandbox" => "workspace-write",
          "loop_policy" => {
            "max_rounds" => 80,
          },
        },
        resolved_model_selection_snapshot: {}
      )
      workflow_run = Workflows::CreateForTurn.call(
        turn: turn,
        root_node_key: "turn_step",
        root_node_type: "turn_step",
        decision_source: "system",
        metadata: {},
        selector_source: "slot",
        selector: "role:mock"
      )
    end

    snapshot = nil

    with_stubbed_provider_catalog(catalog) do
      snapshot = Workflows::BuildExecutionSnapshot.call(turn: workflow_run.turn)
    end

    assert_equal(
      {
        "temperature" => 0.4,
        "top_p" => 0.95,
        "top_k" => 20,
        "min_p" => 0.1,
        "presence_penalty" => 0.6,
        "repetition_penalty" => 1.1,
      },
      snapshot.provider_execution.fetch("execution_settings")
    )
    assert_equal(
      {
        "max_rounds" => 80,
        "parallel_tool_calls" => false,
        "max_parallel_tool_calls" => 1,
        "loop_detection" => {
          "enabled" => false,
        },
      },
      snapshot.provider_execution.fetch("loop_policy")
    )
  end

  test "rejects invalid runtime request overrides while building the execution snapshot" do
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Current input",
      resolved_config_snapshot: { "reasoning_effort" => "" },
      resolved_model_selection_snapshot: {}
    )

    error = assert_raises(ActiveRecord::RecordInvalid) { build_execution_snapshot_for!(turn: turn) }

    assert_equal turn, error.record
    assert_includes error.record.errors[:resolved_config_snapshot], "runtime_override reasoning_effort must be present"
  end

  test "filters wrapper-shaped resolved config payloads through runtime override semantics" do
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Current input",
      resolved_config_snapshot: {
        "config" => {
          "temperature" => 0.2,
          "loop_policy" => {
            "max_rounds" => 72,
          },
        },
        "execution_context" => {
          "identity" => {
            "user_id" => context[:user].public_id,
          },
        },
      },
      resolved_model_selection_snapshot: {}
    )

    snapshot = build_execution_snapshot_for!(turn: turn)

    assert_equal(
      ProviderRequestSettingsSchema.for("responses").merge_execution_settings(
        request_defaults: test_provider_catalog_definition
          .dig(:providers, :codex_subscription, :models, "gpt-5.4", :request_defaults),
        runtime_overrides: {}
      ),
      snapshot.provider_execution.fetch("execution_settings")
    )
    assert_equal(
      {
        "max_rounds" => 72,
        "parallel_tool_calls" => false,
        "max_parallel_tool_calls" => 1,
        "loop_detection" => {
          "enabled" => false,
        },
      },
      snapshot.provider_execution.fetch("loop_policy")
    )
  end

  test "rejects invalid provider round budget overrides" do
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Current input",
      resolved_config_snapshot: {
        "loop_policy" => {
          "max_rounds" => 0,
        },
      },
      resolved_model_selection_snapshot: {}
    )

    error = assert_raises(ActiveRecord::RecordInvalid) { build_execution_snapshot_for!(turn: turn) }

    assert_equal turn, error.record
    assert_includes error.record.errors[:resolved_config_snapshot], "runtime_override loop_policy.max_rounds must be an integer between 1 and 256"
  end

  test "freezes root agent context with the main profile and visible tool names" do
    context = prepare_profile_aware_execution_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Current input",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    snapshot = build_execution_snapshot_for!(turn: turn)

    assert_equal "main", snapshot.capability_projection.fetch("profile_key")
    assert_equal false, snapshot.capability_projection.fetch("is_subagent")
    assert_nil snapshot.capability_projection["subagent_connection_id"]
    assert_nil snapshot.capability_projection["parent_subagent_connection_id"]
    assert_nil snapshot.capability_projection["subagent_depth"]
    assert_equal(
      RuntimeCapabilities::ComposeForTurn.call(turn: turn).fetch("tool_catalog").map { |entry| entry.fetch("tool_name") },
      snapshot.capability_projection.fetch("tool_surface").map { |entry| entry.fetch("tool_name") }
    )
  end

  test "freezes child agent context with profile session lineage and allowed tool names" do
    context = prepare_profile_aware_execution_context!(
      profile_catalog: profile_catalog_with_allowed_tool_names(
        main_tool_names: %w[exec_command compact_context] + RuntimeCapabilityContract::RESERVED_SUBAGENT_TOOL_NAMES,
        researcher_tool_names: %w[exec_command subagent_send subagent_wait subagent_close subagent_list]
      )
    )
    root_conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    child_chain = create_subagent_conversation_chain!(
      context: context,
      parent_conversation: root_conversation,
      depth: 1,
      profile_key: "researcher"
    )
    turn = Turns::StartAgentTurn.call(
      conversation: child_chain.fetch(:conversation),
      content: "Delegated input",
      sender_kind: "owner_agent",
      sender_conversation: child_chain.fetch(:subagent_connection).owner_conversation,
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    snapshot = build_execution_snapshot_for!(turn: turn)

    assert_equal "researcher", snapshot.capability_projection.fetch("profile_key")
    assert_equal true, snapshot.capability_projection.fetch("is_subagent")
    assert_equal child_chain.fetch(:subagent_connection).public_id, snapshot.capability_projection.fetch("subagent_connection_id")
    assert_equal child_chain.fetch(:parent_subagent_connection).public_id, snapshot.capability_projection.fetch("parent_subagent_connection_id")
    assert_equal 1, snapshot.capability_projection.fetch("subagent_depth")
    assert_equal(
      RuntimeCapabilities::ComposeForTurn.call(turn: turn).fetch("tool_catalog").map { |entry| entry.fetch("tool_name") },
      snapshot.capability_projection.fetch("tool_surface").map { |entry| entry.fetch("tool_name") }
    )
  end

  private

  def prepare_profile_aware_execution_context!(profile_catalog: default_profile_catalog)
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    activate_agent_definition_version!(
      context,
      tool_catalog: default_tool_catalog("exec_command", "compact_context"),
      profile_catalog: profile_catalog,
      config_schema_snapshot: profile_aware_config_schema_snapshot,
      conversation_override_schema_snapshot: subagent_policy_override_schema_snapshot,
      default_config_snapshot: profile_aware_default_config_snapshot
    )
    context
  end

  def create_subagent_conversation_chain!(context:, parent_conversation:, depth:, profile_key:)
    previous_conversation = parent_conversation
    previous_session = nil

    (depth + 1).times do |index|
      conversation = create_conversation_record!(
        installation: context[:installation],
        workspace: parent_conversation.workspace,
        parent_conversation: previous_conversation,
        kind: "fork",
        addressability: "agent_addressable"
      )
      session = SubagentConnection.create!(
        installation: context[:installation],
        conversation: conversation,
        owner_conversation: previous_conversation,
        parent_subagent_connection: previous_session,
        scope: "conversation",
        profile_key: profile_key,
        depth: index
      )

      previous_conversation = conversation
      previous_session = session
    end

    {
      conversation: previous_conversation,
      subagent_connection: previous_session,
      parent_subagent_connection: previous_session.parent_subagent_connection,
    }
  end

  def profile_catalog_with_allowed_tool_names(main_tool_names:, researcher_tool_names:)
    default_profile_catalog.deep_merge(
      "main" => { "allowed_tool_names" => main_tool_names },
      "researcher" => { "allowed_tool_names" => researcher_tool_names }
    )
  end
end
