require "test_helper"

class Workflows::ManualRetryTest < ActiveSupport::TestCase
  test "preserves the paused workflow as history and starts a fresh workflow from the last stable input" do
    context = build_paused_recovery_context!
    replacement = create_compatible_replacement_deployment!(
      installation: context[:installation],
      agent_program: context[:agent_program],
      execution_runtime: context[:execution_runtime]
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
    assert_equal replacement, retried.turn.agent_program_version
    assert_equal replacement.fingerprint, retried.turn.pinned_program_version_fingerprint
    assert_equal "candidate:openai/gpt-5.3-chat-latest", retried.turn.normalized_selector
    assert_equal "openai", retried.turn.resolved_provider_handle
    assert_equal "gpt-5.3-chat-latest", retried.turn.resolved_model_ref
    assert_equal replacement.public_id, retried.execution_identity["agent_program_version_id"]
    assert_equal context[:execution_runtime].public_id, retried.execution_identity["execution_runtime_id"]
    assert_equal ["root"], retried.workflow_nodes.order(:ordinal).pluck(:node_key)

    paused = context[:workflow_run].reload
    assert paused.canceled?
    assert paused.turn.reload.canceled?
    assert_equal context[:turn].selected_input_message.content, retried.turn.selected_input_message.content
    assert_equal context[:agent_program], context[:conversation].reload.agent_program

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
        deployment: context[:agent_program_version],
        actor: create_user!(installation: context[:installation], role: "admin")
      )
    end

    assert_includes error.record.errors[:deletion_state], "must be retained before manual retry"
  end

  test "rejects manual retry when the replacement deployment belongs to another execution environment" do
    context = build_paused_recovery_context!
    replacement = create_compatible_replacement_deployment!(
      installation: context[:installation],
      agent_program: context[:agent_program]
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Workflows::ManualRetry.call(
        workflow_run: context[:workflow_run],
        deployment: replacement,
        actor: create_user!(installation: context[:installation], role: "admin")
      )
    end

    assert_includes error.record.errors[:agent_program_version], "must preserve the frozen execution runtime"
  end

  test "rejects manual retry when the frozen selector can no longer be resolved" do
    context = build_paused_recovery_context!
    replacement = create_compatible_replacement_deployment!(
      installation: context[:installation],
      agent_program: context[:agent_program],
      execution_runtime: context[:execution_runtime]
    )
    ProviderEntitlement.where(installation: context[:installation]).update_all(active: false)

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Workflows::ManualRetry.call(
        workflow_run: context[:workflow_run],
        deployment: replacement,
        actor: create_user!(installation: context[:installation], role: "admin")
      )
    end

    assert_equal context[:turn].id, error.record.id
    assert_includes error.record.errors[:resolved_model_selection_snapshot], "must remain resolvable for the recovery action"
    assert context[:workflow_run].reload.waiting?
    assert context[:turn].reload.active?
    assert_equal context[:agent_program], context[:conversation].reload.agent_program
  end

  test "rechecks paused recovery state after acquiring the conversation lock" do
    context = build_paused_recovery_context!
    replacement = create_compatible_replacement_deployment!(
      installation: context[:installation],
      agent_program: context[:agent_program],
      execution_runtime: context[:execution_runtime]
    )
    service = Workflows::ManualRetry.new(
      workflow_run: context[:workflow_run],
      deployment: replacement,
      actor: create_user!(installation: context[:installation], role: "admin")
    )
    inject_ready_state_after_initial_check!(service, context[:workflow_run])

    error = assert_raises(ActiveRecord::RecordInvalid) do
      service.call
    end

    assert_includes error.record.errors[:wait_reason_kind], "must require manual recovery before retrying"
    assert context[:workflow_run].reload.ready?
    assert_equal context[:agent_program], context[:conversation].reload.agent_program
    assert_equal 1, context[:conversation].turns.count
  end

  test "manual retry reuses the canonical paused-work recovery target resolver" do
    context = build_paused_recovery_context!
    replacement = create_compatible_replacement_deployment!(
      installation: context[:installation],
      agent_program: context[:agent_program],
      execution_runtime: context[:execution_runtime]
    )
    original_resolve_call = nil
    resolve_calls = []

    original_resolve_call = AgentProgramVersions::ResolveRecoveryTarget.method(:call)
    AgentProgramVersions::ResolveRecoveryTarget.singleton_class.define_method(:call) do |*args, **kwargs|
      resolve_calls << kwargs
      original_resolve_call.call(*args, **kwargs)
    end

    retried = Workflows::ManualRetry.call(
      workflow_run: context[:workflow_run],
      deployment: replacement,
      actor: create_user!(installation: context[:installation], role: "admin"),
      selector: "role:planner"
    )

    assert retried.active?
    assert_equal 1, resolve_calls.size
    assert_equal context[:turn].id, resolve_calls.first.fetch(:turn).id
    assert_equal replacement, resolve_calls.first.fetch(:agent_program_version)
    assert_equal "manual_recovery", resolve_calls.first.fetch(:selector_source)
  ensure
    if original_resolve_call
      AgentProgramVersions::ResolveRecoveryTarget.singleton_class.define_method(:call, original_resolve_call)
    end
  end

  private

  def build_paused_recovery_context!
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_program_version: context[:agent_program_version]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Paused retry input",
      agent_program_version: context[:agent_program_version],
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
    AgentProgramVersions::MarkUnavailable.call(
      deployment: context[:agent_program_version],
      severity: "prolonged",
      reason: "runtime_offline",
      occurred_at: Time.current
    )

    context.merge(conversation: conversation, turn: turn.reload, workflow_run: workflow_run.reload)
  end

  def create_compatible_replacement_deployment!(
    installation:,
    agent_program:,
    execution_runtime: create_execution_runtime!(installation: installation)
  )
    AgentSession.where(agent_program: agent_program, lifecycle_state: "active").update_all(
      lifecycle_state: "stale",
      updated_at: Time.current
    )
    deployment = create_agent_program_version!(
      installation: installation,
      agent_program: agent_program,
      fingerprint: "replacement-#{next_test_sequence}",
      protocol_methods: default_protocol_methods("agent_health", "capabilities_handshake", "conversation_transcript_list"),
      tool_catalog: default_tool_catalog("exec_command", "workspace_variables_get"),
      config_schema_snapshot: default_config_schema_snapshot(include_selector_slots: true),
      default_config_snapshot: default_default_config_snapshot(include_selector_slots: true)
    )
    agent_program.update!(default_execution_runtime: execution_runtime)
    create_agent_session!(
      installation: installation,
      agent_program: agent_program,
      agent_program_version: deployment,
      health_status: "healthy",
      auto_resume_eligible: true,
      last_heartbeat_at: Time.current,
      last_health_check_at: Time.current
    )
    ExecutionSession.where(execution_runtime: execution_runtime, lifecycle_state: "active").update_all(
      lifecycle_state: "stale",
      updated_at: Time.current
    )
    create_execution_session!(
      installation: installation,
      execution_runtime: execution_runtime,
      last_heartbeat_at: Time.current
    )

    deployment
  end

  def inject_ready_state_after_initial_check!(service, workflow_run)
    injected = false

    service.singleton_class.prepend(Module.new do
      define_method(:validate_retry_state!) do |current_workflow_run = @workflow_run|
        super(current_workflow_run).tap do
          next if injected

          injected = true
          workflow_run.update!(
            wait_state: "ready",
            wait_reason_kind: nil,
            wait_reason_payload: {},
            waiting_since_at: nil,
            blocking_resource_type: nil,
            blocking_resource_id: nil
          )
        end
      end
    end)
  end
end
