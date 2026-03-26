require "test_helper"

class Conversations::ValidateAgentDeploymentTargetTest < ActiveSupport::TestCase
  test "rejects a deployment from another installation" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    replacement = AgentDeployment.new(
      installation_id: context[:installation].id + 1,
      agent_installation: context[:agent_installation],
      execution_environment: context[:execution_environment],
      fingerprint: "replacement-#{next_test_sequence}",
      protocol_version: "2026-03-24",
      sdk_version: "validator-test",
      machine_credential_digest: "digest-#{next_test_sequence}",
      endpoint_metadata: {},
      health_metadata: {},
      bootstrap_state: "pending",
      health_status: "healthy",
      realtime_link_state: "disconnected",
      control_activity_state: "offline"
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::ValidateAgentDeploymentTarget.call(
        conversation: conversation,
        agent_deployment: replacement
      )
    end

    assert_same conversation, error.record
    assert_includes error.record.errors[:agent_deployment], "must belong to the same installation"
  end

  test "rejects a deployment outside the bound execution environment" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    replacement = create_agent_deployment!(
      installation: context[:installation],
      agent_installation: context[:agent_installation],
      execution_environment: create_execution_environment!(installation: context[:installation]),
      fingerprint: "replacement-#{next_test_sequence}",
      bootstrap_state: "pending"
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::ValidateAgentDeploymentTarget.call(
        conversation: conversation,
        agent_deployment: replacement
      )
    end

    assert_same conversation, error.record
    assert_includes error.record.errors[:agent_deployment], "must belong to the bound execution environment"
  end

  test "rejects a replacement deployment from a different logical agent when continuity is required" do
    context = build_turn_context!
    replacement = create_replacement_deployment!(
      installation: context[:installation],
      agent_installation: create_agent_installation!(installation: context[:installation]),
      execution_environment: context[:execution_environment]
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::ValidateAgentDeploymentTarget.call(
        conversation: context[:conversation],
        agent_deployment: replacement,
        record: context[:turn],
        same_logical_agent_as: context[:turn].agent_deployment
      )
    end

    assert_same context[:turn], error.record
    assert_includes error.record.errors[:agent_deployment], "must belong to the same logical agent installation"
  end

  test "rejects a replacement deployment that does not preserve the paused capability contract" do
    context = build_turn_context!
    replacement = create_replacement_deployment!(
      installation: context[:installation],
      agent_installation: context[:agent_installation],
      execution_environment: context[:execution_environment],
      protocol_methods: default_protocol_methods("agent_health"),
      tool_catalog: default_tool_catalog("shell_exec")
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::ValidateAgentDeploymentTarget.call(
        conversation: context[:conversation],
        agent_deployment: replacement,
        record: context[:turn],
        capability_contract_turn: context[:turn]
      )
    end

    assert_same context[:turn], error.record
    assert_includes error.record.errors[:agent_deployment], "must preserve the paused workflow capability contract"
  end

  private

  def build_turn_context!
    context = prepare_workflow_execution_context!(create_workspace_context!)
    richer_snapshot = create_capability_snapshot!(
      agent_deployment: context[:agent_deployment],
      version: 2,
      protocol_methods: default_protocol_methods(
        "agent_health",
        "capabilities_handshake",
        "conversation_transcript_list"
      ),
      tool_catalog: default_tool_catalog("shell_exec", "workspace_variables_get"),
      config_schema_snapshot: default_config_schema_snapshot(include_selector_slots: true),
      default_config_snapshot: default_default_config_snapshot(include_selector_slots: true)
    )
    context[:agent_deployment].update!(active_capability_snapshot: richer_snapshot)
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Shared deployment validator input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    Workflows::CreateForTurn.call(
      turn: turn,
      root_node_key: "root",
      root_node_type: "turn_root",
      decision_source: "system",
      metadata: {}
    )

    context.merge(conversation: conversation, turn: turn.reload)
  end

  def create_replacement_deployment!(
    installation:,
    agent_installation:,
    execution_environment:,
    protocol_methods: default_protocol_methods("agent_health", "capabilities_handshake", "conversation_transcript_list"),
    tool_catalog: default_tool_catalog("shell_exec", "workspace_variables_get")
  )
    agent_installation.agent_deployments.where(bootstrap_state: "active").update_all(
      bootstrap_state: "superseded",
      updated_at: Time.current
    )

    deployment = create_agent_deployment!(
      installation: installation,
      agent_installation: agent_installation,
      execution_environment: execution_environment,
      fingerprint: "replacement-#{next_test_sequence}",
      health_status: "healthy",
      auto_resume_eligible: true
    )
    capability_snapshot = create_capability_snapshot!(
      agent_deployment: deployment,
      version: 1,
      protocol_methods: protocol_methods,
      tool_catalog: tool_catalog,
      config_schema_snapshot: default_config_schema_snapshot(include_selector_slots: true),
      default_config_snapshot: default_default_config_snapshot(include_selector_slots: true)
    )
    deployment.update!(active_capability_snapshot: capability_snapshot)

    deployment
  end
end
