require "test_helper"

module AppendOnly
end

class AppendOnly::ConversationAndTurnAllocationTest < NonTransactionalConcurrencyTestCase
  test "allocates unique sequences for concurrent user turns in one conversation" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    deployment_id = context[:agent_deployment].id

    turns = assert_parallel_success!(
      run_in_parallel(10) do |index|
        Turns::StartUserTurn.call(
          conversation: Conversation.find(conversation.id),
          content: "Input #{index}",
          agent_deployment: AgentDeployment.find(deployment_id),
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
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    ),
      content: "Original input",
      agent_deployment: context[:agent_deployment],
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

  test "reuses one reconciled capability snapshot version across concurrent handshakes" do
    registration = register_agent_runtime!(
      config_schema_snapshot: default_config_schema_snapshot(include_selector_slots: true),
      default_config_snapshot: default_default_config_snapshot(include_selector_slots: true)
    )
    deployment_id = registration[:deployment].id
    expected_tool_catalog = default_tool_catalog("exec_command", "subagent_spawn")

    results = assert_parallel_success!(
      run_in_parallel(5) do
        AgentDeployments::Handshake.call(
          deployment: AgentDeployment.find(deployment_id),
          fingerprint: registration[:deployment].fingerprint,
          protocol_version: "2026-03-25",
          sdk_version: "fenix-0.2.0",
          protocol_methods: default_protocol_methods("agent_health", "capabilities_handshake", "capabilities_refresh"),
          tool_catalog: expected_tool_catalog,
          profile_catalog: default_profile_catalog,
          config_schema_snapshot: default_config_schema_snapshot(include_selector_slots: true),
          conversation_override_schema_snapshot: { "type" => "object", "properties" => {} },
          default_config_snapshot: {
            "sandbox" => "workspace-read",
            "interactive" => { "selector" => "role:main" },
          }
        )
      end
    )

    snapshots = CapabilitySnapshot.where(agent_deployment_id: deployment_id).order(:version)
    normalized_tool_catalog = RuntimeCapabilityContract.build(tool_catalog: expected_tool_catalog).agent_tool_catalog

    assert_equal [1, 2], snapshots.pluck(:version)
    assert results.all? { |result| result.capability_snapshot.version == 2 }
    assert_equal normalized_tool_catalog, registration[:deployment].reload.active_capability_snapshot.tool_catalog
  end

  test "reuses one reconciled bundled capability snapshot version across concurrent registration passes" do
    installation = create_installation!
    initial = Installations::RegisterBundledAgentRuntime.call(
      installation: installation,
      configuration: bundled_agent_configuration(enabled: true)
    )
    updated_configuration = bundled_agent_configuration(
      enabled: true,
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

    deployment = initial.deployment.reload

    assert_equal [1, 2], deployment.capability_snapshots.order(:version).pluck(:version)
    assert results.all? { |result| result.deployment.id == deployment.id }
    assert results.all? { |result| result.capability_snapshot.version == 2 }
    assert_equal "fenix-0.2.0", deployment.sdk_version
  end
end
