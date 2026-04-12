require "test_helper"

module AppendOnly
end

class AppendOnly::ConversationAndTurnAllocationTest < NonTransactionalConcurrencyTestCase
  test "allocates unique sequences for concurrent user turns in one conversation" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version]
    )
    agent_definition_version_id = context[:agent_definition_version].id

    turns = assert_parallel_success!(
      run_in_parallel(10) do |index|
        Turns::StartUserTurn.call(
          conversation: Conversation.find(conversation.id),
          content: "Input #{index}",
          agent_definition_version: AgentDefinitionVersion.find(agent_definition_version_id),
          resolved_config_snapshot: {},
          resolved_model_selection_snapshot: {}
        )
      end
    )

    assert_equal (1..10).to_a, turns.map(&:sequence).sort
    assert_equal (1..10).to_a, Turn.where(conversation: conversation).order(:sequence).pluck(:sequence)
  end

  test "allocates unique input variants for concurrent steer operations" do
    context = create_workspace_context!
    turn = Turns::StartUserTurn.call(
      conversation: Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version]
    ),
      content: "Original input",
      agent_definition_version: context[:agent_definition_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    updated_turns = assert_parallel_success!(
      run_in_parallel(2) do |index|
        Turns::SteerCurrentInput.call(
          turn: Turn.find(turn.id),
          content: "Steered input #{index}"
        )
      end
    )

    assert_equal [1, 2], updated_turns.map { |updated_turn| updated_turn.selected_input_message.variant_index }.sort
    assert_equal [0, 1, 2], UserMessage.where(turn: turn).order(:variant_index).pluck(:variant_index)
  end

  test "allocates unique projection sequences and stream revisions for concurrent conversation events" do
    context = build_human_interaction_context!
    conversation = context[:conversation]

    events = assert_parallel_success!(
      run_in_parallel(10) do |index|
        ConversationEvents::Project.call(
          conversation: Conversation.find(conversation.id),
          event_kind: "runtime.status",
          stream_key: "status-card",
          payload: { "state" => "update-#{index}" }
        )
      end
    )

    assert_equal (0..9).to_a, events.map(&:projection_sequence).sort
    assert_equal (0..9).to_a, events.map(&:stream_revision).sort
    assert_equal (0..9).to_a, ConversationEvent.where(conversation: conversation).order(:projection_sequence).pluck(:projection_sequence)
    assert_equal (0..9).to_a, ConversationEvent.where(conversation: conversation, stream_key: "status-card").order(:stream_revision).pluck(:stream_revision)
  end

  test "reuses one authenticated agent definition version across concurrent handshakes" do
    registration = register_agent_runtime!(
      config_schema_snapshot: default_config_schema_snapshot(include_selector_slots: true),
      default_config_snapshot: default_default_config_snapshot(include_selector_slots: true)
    )
    agent_definition_version_id = registration[:agent_definition_version].id
    definition_package = {
      "program_manifest_fingerprint" => registration[:agent_definition_version].program_manifest_fingerprint,
      "prompt_pack_ref" => registration[:agent_definition_version].prompt_pack_ref,
      "prompt_pack_fingerprint" => registration[:agent_definition_version].prompt_pack_fingerprint,
      "protocol_version" => registration[:agent_definition_version].protocol_version,
      "sdk_version" => registration[:agent_definition_version].sdk_version,
      "protocol_methods" => registration[:agent_definition_version].protocol_methods,
      "tool_contract" => registration[:agent_definition_version].tool_contract,
      "profile_policy" => registration[:agent_definition_version].profile_policy,
      "canonical_config_schema" => registration[:agent_definition_version].canonical_config_schema,
      "conversation_override_schema" => registration[:agent_definition_version].conversation_override_schema,
      "default_canonical_config" => registration[:agent_definition_version].default_canonical_config,
      "reflected_surface" => registration[:agent_definition_version].reflected_surface,
    }

    results = assert_parallel_success!(
      run_in_parallel(5) do
        AgentDefinitionVersions::Handshake.call(
          agent_connection: AgentConnection.find(registration[:agent_connection].id),
          definition_package: definition_package
        )
      end
    )

    tool_definition_names = registration[:agent_definition_version].reload.tool_definitions.order(:tool_name).pluck(:tool_name)

    assert results.all? { |result| result.agent_definition_version.id == agent_definition_version_id }
    assert_equal tool_definition_names.uniq, tool_definition_names
    assert_equal 1, registration[:agent_definition_version].reload.tool_definitions.where(tool_name: "subagent_spawn").count
  end

  test "reuses one bundled agent definition version across concurrent registration passes for the same fingerprint" do
    installation = create_installation!
    initial = Installations::RegisterBundledAgentRuntime.call(
      installation: installation,
      configuration: bundled_agent_configuration(enabled: true)
    )
    updated_configuration = bundled_agent_configuration(
      enabled: true,
      fingerprint: "bundled-fenix-runtime-v2",
      sdk_version: "fenix-0.2.0",
      tool_catalog: default_tool_catalog("exec_command", "subagent_spawn")
    )

    results = assert_parallel_success!(
      run_in_parallel(5) do
        Installations::RegisterBundledAgentRuntime.call(
          installation: Installation.find(installation.id),
          configuration: updated_configuration
        )
      end
    )

    agent_definition_version = results.first.agent_definition_version.reload

    assert results.all? { |result| result.agent_definition_version.id == agent_definition_version.id }
    assert results.all? { |result| result.agent_definition_version.id == agent_definition_version.id }
    assert_equal 2, AgentDefinitionVersion.where(agent: initial.agent).count
    assert_equal "fenix-0.2.0", agent_definition_version.sdk_version
    assert_equal "active", agent_definition_version.bootstrap_state
    assert_equal 1, AgentConnection.where(agent: initial.agent, lifecycle_state: "active").count
  end
end
