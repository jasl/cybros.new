require "test_helper"

class Workflows::ManualResumeTest < ActiveSupport::TestCase
  test "resumes a paused workflow on a compatible replacement deployment with a one time override" do
    context = build_paused_recovery_context!
    replacement = create_compatible_replacement_deployment!(
      installation: context[:installation],
      agent_installation: context[:agent_installation],
      execution_environment: context[:execution_environment],
      selector_snapshot: default_default_config_snapshot(include_selector_slots: true)
    )
    actor = create_user!(installation: context[:installation], role: "admin")

    resumed = Workflows::ManualResume.call(
      workflow_run: context[:workflow_run],
      deployment: replacement,
      actor: actor,
      selector: "role:planner"
    )

    assert_equal context[:workflow_run].id, resumed.id
    assert resumed.ready?
    assert_equal replacement, resumed.turn.reload.agent_deployment
    assert_equal replacement.fingerprint, resumed.turn.pinned_deployment_fingerprint
    assert_equal "role:planner", resumed.turn.normalized_selector
    assert_equal "openai", resumed.turn.resolved_provider_handle
    assert_equal "gpt-5.4", resumed.turn.resolved_model_ref
    assert_equal replacement.public_id, resumed.execution_identity["agent_deployment_id"]

    conversation = context[:conversation].reload
    assert_equal replacement, conversation.agent_deployment
    assert_equal "auto", conversation.interactive_selector_mode
    assert_nil conversation.interactive_selector_provider_handle
    assert_nil conversation.interactive_selector_model_ref
    assert_equal(
      default_default_config_snapshot(include_selector_slots: true),
      replacement.active_capability_snapshot.default_config_snapshot
    )

    audit_log = AuditLog.find_by!(action: "workflow.manual_resumed")
    assert_equal actor, audit_log.actor
    assert_equal resumed, audit_log.subject
    assert_equal replacement.id, audit_log.metadata["deployment_id"]
    assert_equal "role:planner", audit_log.metadata["temporary_selector_override"]
  end

  test "rejects manual resume when the replacement deployment belongs to a different logical agent" do
    context = build_paused_recovery_context!
    other_installation = create_agent_installation!(installation: context[:installation])
    replacement = create_compatible_replacement_deployment!(
      installation: context[:installation],
      agent_installation: other_installation,
      execution_environment: context[:execution_environment]
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Workflows::ManualResume.call(
        workflow_run: context[:workflow_run],
        deployment: replacement,
        actor: create_user!(installation: context[:installation], role: "admin")
      )
    end

    assert_includes error.record.errors[:agent_deployment], "must belong to the same logical agent installation"
  end

  test "rejects manual resume when required capabilities are no longer available" do
    context = build_paused_recovery_context!
    replacement = create_compatible_replacement_deployment!(
      installation: context[:installation],
      agent_installation: context[:agent_installation],
      execution_environment: context[:execution_environment],
      protocol_methods: default_protocol_methods("agent_health"),
      tool_catalog: default_tool_catalog("shell_exec")
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Workflows::ManualResume.call(
        workflow_run: context[:workflow_run],
        deployment: replacement,
        actor: create_user!(installation: context[:installation], role: "admin")
      )
    end

    assert_includes error.record.errors[:agent_deployment], "must preserve the paused workflow capability contract"
  end

  test "rejects manual resume when the frozen selector can no longer be resolved" do
    context = build_paused_recovery_context!
    replacement = create_compatible_replacement_deployment!(
      installation: context[:installation],
      agent_installation: context[:agent_installation],
      execution_environment: context[:execution_environment]
    )
    ProviderEntitlement.where(installation: context[:installation]).update_all(active: false)

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Workflows::ManualResume.call(
        workflow_run: context[:workflow_run],
        deployment: replacement,
        actor: create_user!(installation: context[:installation], role: "admin")
      )
    end

    assert_includes error.record.errors[:resolved_model_selection_snapshot], "must remain resolvable for the recovery action"
  end

  test "rejects manual resume for pending delete conversations" do
    context = build_paused_recovery_context!
    context[:conversation].update!(deletion_state: "pending_delete", deleted_at: Time.current)

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Workflows::ManualResume.call(
        workflow_run: context[:workflow_run],
        deployment: context[:agent_deployment],
        actor: create_user!(installation: context[:installation], role: "admin")
      )
    end

    assert_includes error.record.errors[:deletion_state], "must be retained before manual recovery"
  end

  test "rejects manual resume when the replacement deployment belongs to another execution environment" do
    context = build_paused_recovery_context!
    replacement = create_compatible_replacement_deployment!(
      installation: context[:installation],
      agent_installation: context[:agent_installation]
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Workflows::ManualResume.call(
        workflow_run: context[:workflow_run],
        deployment: replacement,
        actor: create_user!(installation: context[:installation], role: "admin")
      )
    end

    assert_includes error.record.errors[:agent_deployment], "must belong to the bound execution environment"
  end

  private

  def build_paused_recovery_context!
    context = prepare_workflow_execution_context!(create_workspace_context!)
    richer_snapshot = create_capability_snapshot!(
      agent_deployment: context[:agent_deployment],
      version: 2,
      protocol_methods: default_protocol_methods("agent_health", "capabilities_handshake", "conversation_transcript_list"),
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
      content: "Paused recovery input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    workflow_run = Workflows::CreateForTurn.call(
      turn: turn,
      root_node_key: "root",
      root_node_type: "turn_root",
      decision_source: "system",
      metadata: {}
    )
    AgentDeployments::MarkUnavailable.call(
      deployment: context[:agent_deployment],
      severity: "prolonged",
      reason: "runtime_offline",
      occurred_at: Time.current
    )

    context.merge(conversation: conversation, turn: turn.reload, workflow_run: workflow_run.reload)
  end

  def create_compatible_replacement_deployment!(
    installation:,
    agent_installation:,
    execution_environment: create_execution_environment!(installation: installation),
    protocol_methods: default_protocol_methods("agent_health", "capabilities_handshake", "conversation_transcript_list"),
    tool_catalog: default_tool_catalog("shell_exec", "workspace_variables_get"),
    selector_snapshot: default_default_config_snapshot(include_selector_slots: true)
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
      default_config_snapshot: selector_snapshot
    )
    deployment.update!(active_capability_snapshot: capability_snapshot)

    deployment
  end
end
