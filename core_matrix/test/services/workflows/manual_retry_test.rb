require "test_helper"

class Workflows::ManualRetryTest < ActiveSupport::TestCase
  test "preserves the paused workflow as history and starts a fresh workflow from the last stable input" do
    context = build_paused_recovery_context!
    replacement = create_compatible_replacement_deployment!(
      installation: context[:installation],
      agent_installation: context[:agent_installation]
    )
    actor = create_user!(installation: context[:installation], role: "admin")

    retried = Workflows::ManualRetry.call(
      workflow_run: context[:workflow_run],
      deployment: replacement,
      actor: actor,
      selector: "candidate:openai/gpt-5.3-chat-latest"
    )

    assert retried.active?
    assert_not_equal context[:workflow_run].id, retried.id
    assert_equal "Paused retry input", retried.turn.selected_input_message.content
    assert_equal replacement, retried.turn.agent_deployment
    assert_equal replacement.fingerprint, retried.turn.pinned_deployment_fingerprint
    assert_equal "candidate:openai/gpt-5.3-chat-latest", retried.turn.normalized_selector
    assert_equal "openai", retried.turn.resolved_provider_handle
    assert_equal "gpt-5.3-chat-latest", retried.turn.resolved_model_ref
    assert_equal ["root"], retried.workflow_nodes.order(:ordinal).pluck(:node_key)

    paused = context[:workflow_run].reload
    assert paused.canceled?
    assert paused.turn.reload.canceled?
    assert_equal context[:turn].selected_input_message.content, retried.turn.selected_input_message.content

    audit_log = AuditLog.find_by!(action: "workflow.manual_retried")
    assert_equal actor, audit_log.actor
    assert_equal retried, audit_log.subject
    assert_equal paused.id, audit_log.metadata["paused_workflow_run_id"]
    assert_equal "candidate:openai/gpt-5.3-chat-latest", audit_log.metadata["temporary_selector_override"]
  end

  test "rejects manual retry for pending delete conversations" do
    context = build_paused_recovery_context!
    context[:conversation].update!(deletion_state: "pending_delete", deleted_at: Time.current)

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Workflows::ManualRetry.call(
        workflow_run: context[:workflow_run],
        deployment: context[:agent_deployment],
        actor: create_user!(installation: context[:installation], role: "admin")
      )
    end

    assert_includes error.record.errors[:deletion_state], "must be retained before manual retry"
  end

  private

  def build_paused_recovery_context!
    context = prepare_workflow_execution_context!(create_workspace_context!)
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Paused retry input",
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

  def create_compatible_replacement_deployment!(installation:, agent_installation:)
    agent_installation.agent_deployments.where(bootstrap_state: "active").update_all(
      bootstrap_state: "superseded",
      updated_at: Time.current
    )
    environment = create_execution_environment!(installation: installation)
    deployment = create_agent_deployment!(
      installation: installation,
      agent_installation: agent_installation,
      execution_environment: environment,
      fingerprint: "replacement-#{next_test_sequence}",
      health_status: "healthy",
      auto_resume_eligible: true
    )
    capability_snapshot = create_capability_snapshot!(
      agent_deployment: deployment,
      version: 1,
      protocol_methods: default_protocol_methods("agent_health", "capabilities_handshake", "conversation_transcript_list"),
      tool_catalog: default_tool_catalog("shell_exec", "workspace_variables_get"),
      config_schema_snapshot: default_config_schema_snapshot(include_selector_slots: true),
      default_config_snapshot: default_default_config_snapshot(include_selector_slots: true)
    )
    deployment.update!(active_capability_snapshot: capability_snapshot)

    deployment
  end
end
