require "test_helper"

class AgentProgramVersions::AutoResumeWorkflowsTest < ActiveSupport::TestCase
  test "automatically resumes waiting workflows when runtime identity did not drift" do
    context = build_waiting_recovery_context!
    assert_equal context[:agent_program_version].public_id, context[:workflow_run].reload.blocking_resource_id

    AgentProgramVersions::RecordHeartbeat.call(
      deployment: context[:agent_program_version],
      health_status: "healthy",
      health_metadata: {},
      auto_resume_eligible: true
    )

    resumed = AgentProgramVersions::AutoResumeWorkflows.call(deployment: context[:agent_program_version])

    assert_equal [context[:workflow_run].id], resumed.map(&:id)

    workflow_run = context[:workflow_run].reload
    assert workflow_run.ready?
    assert_nil workflow_run.wait_reason_kind
    assert_equal({}, workflow_run.wait_reason_payload)
    assert_nil workflow_run.blocking_resource_type
    assert_nil workflow_run.blocking_resource_id
  end

  test "requires explicit manual recovery when capabilities drift while waiting" do
    context = build_waiting_recovery_context!
    drifted_snapshot = create_capability_snapshot!(
      agent_program_version: context[:agent_program_version],
      version: 3,
      protocol_methods: default_protocol_methods("agent_health", "capabilities_handshake", "conversation_transcript_list"),
      tool_catalog: default_tool_catalog("exec_command"),
      default_config_snapshot: {
        "sandbox" => "workspace-read",
      }
    )
    adopt_agent_program_version!(context, drifted_snapshot, turn: nil)

    AgentProgramVersions::RecordHeartbeat.call(
      deployment: context[:agent_program_version],
      health_status: "healthy",
      health_metadata: {},
      auto_resume_eligible: true
    )

    resumed = AgentProgramVersions::AutoResumeWorkflows.call(deployment: context[:agent_program_version])

    assert_equal [], resumed

    workflow_run = context[:workflow_run].reload
    assert workflow_run.waiting?
    assert_equal "manual_recovery_required", workflow_run.wait_reason_kind
    assert_equal "paused_agent_unavailable", workflow_run.recovery_state
    assert_equal "capability_contract_drift", workflow_run.recovery_drift_reason
  end

  test "ignores waiting workflows whose conversations are pending delete" do
    context = build_waiting_recovery_context!
    context[:conversation].update!(deletion_state: "pending_delete", deleted_at: Time.current)

    AgentProgramVersions::RecordHeartbeat.call(
      deployment: context[:agent_program_version],
      health_status: "healthy",
      health_metadata: {},
      auto_resume_eligible: true
    )

    assert_equal [], AgentProgramVersions::AutoResumeWorkflows.call(deployment: context[:agent_program_version])
    assert context[:workflow_run].reload.waiting?
  end

  test "compatible rotated deployment auto resumes waiting workflows and rewrites turn pinning" do
    context = build_waiting_recovery_context!
    replacement = create_compatible_replacement_deployment!(
      installation: context[:installation],
      agent_program: context[:agent_program],
      executor_program: context[:executor_program]
    )

    AgentProgramVersions::RecordHeartbeat.call(
      deployment: replacement,
      health_status: "healthy",
      health_metadata: { "release" => "fenix-0.2.0" },
      auto_resume_eligible: true
    )

    resumed = AgentProgramVersions::AutoResumeWorkflows.call(deployment: replacement)

    assert_equal [context[:workflow_run].id], resumed.map(&:id)
    assert_equal context[:agent_program], context[:conversation].reload.agent_program
    turn = context[:turn].reload
    assert_equal replacement, turn.agent_program_version
    assert_equal replacement.fingerprint, turn.pinned_program_version_fingerprint
    assert_equal replacement.public_id, turn.execution_snapshot.identity["agent_program_version_id"]
    assert context[:workflow_run].reload.ready?
  end

  test "compatible rotated deployment auto resumes through the canonical rebinding owner" do
    context = build_waiting_recovery_context!
    replacement = create_compatible_replacement_deployment!(
      installation: context[:installation],
      agent_program: context[:agent_program],
      executor_program: context[:executor_program]
    )
    original_rebind_call = nil
    rebind_calls = []

    AgentProgramVersions::RecordHeartbeat.call(
      deployment: replacement,
      health_status: "healthy",
      health_metadata: { "release" => "fenix-0.2.0" },
      auto_resume_eligible: true
    )

    original_rebind_call = AgentProgramVersions::RebindTurn.method(:call)
    AgentProgramVersions::RebindTurn.singleton_class.define_method(:call) do |*args, **kwargs|
      rebind_calls << kwargs
      original_rebind_call.call(*args, **kwargs)
    end

    resumed = AgentProgramVersions::AutoResumeWorkflows.call(deployment: replacement)

    assert_equal [context[:workflow_run].id], resumed.map(&:id)
    assert_equal 1, rebind_calls.size
    assert_equal context[:turn].id, rebind_calls.first.fetch(:turn).id
    assert_equal replacement, rebind_calls.first.fetch(:recovery_target).agent_program_version
  ensure
    if original_rebind_call
      AgentProgramVersions::RebindTurn.singleton_class.define_method(:call, original_rebind_call)
    end
  end

  test "cross environment rotated deployments require manual recovery instead of auto resume" do
    context = build_waiting_recovery_context!
    replacement = create_compatible_replacement_deployment!(
      installation: context[:installation],
      agent_program: context[:agent_program]
    )

    AgentProgramVersions::RecordHeartbeat.call(
      deployment: replacement,
      health_status: "healthy",
      health_metadata: { "release" => "fenix-0.2.0" },
      auto_resume_eligible: true
    )

    resumed = AgentProgramVersions::AutoResumeWorkflows.call(deployment: replacement)

    assert_equal [], resumed
    assert_equal context[:agent_program], context[:conversation].reload.agent_program
    assert_equal context[:agent_program_version], context[:turn].reload.agent_program_version
    assert_equal "manual_recovery_required", context[:workflow_run].reload.wait_reason_kind
    assert_equal "executor_program_drift", context[:workflow_run].recovery_drift_reason
  end

  test "restores the original human-interaction blocker after auto resume" do
    context = build_waiting_human_interaction_recovery_context!

    AgentProgramVersions::RecordHeartbeat.call(
      deployment: context[:agent_program_version],
      health_status: "healthy",
      health_metadata: {},
      auto_resume_eligible: true
    )

    resumed = AgentProgramVersions::AutoResumeWorkflows.call(deployment: context[:agent_program_version])

    assert_equal [context[:workflow_run].id], resumed.map(&:id)

    workflow_run = context[:workflow_run].reload
    assert workflow_run.waiting?
    assert_equal "human_interaction", workflow_run.wait_reason_kind
    assert_equal "HumanInteractionRequest", workflow_run.blocking_resource_type
    assert_equal context[:request].public_id, workflow_run.blocking_resource_id
    assert_equal({}, workflow_run.wait_reason_payload)
  end

  test "does not restore a human-interaction blocker that was resolved during the outage" do
    context = build_waiting_human_interaction_recovery_context!

    HumanInteractions::CompleteTask.call(
      human_task_request: context[:request],
      completion_payload: { "approved" => true }
    )

    AgentProgramVersions::RecordHeartbeat.call(
      deployment: context[:agent_program_version],
      health_status: "healthy",
      health_metadata: {},
      auto_resume_eligible: true
    )

    resumed = AgentProgramVersions::AutoResumeWorkflows.call(deployment: context[:agent_program_version])

    assert_equal [context[:workflow_run].id], resumed.map(&:id)

    workflow_run = context[:workflow_run].reload
    assert workflow_run.ready?
    assert_nil workflow_run.wait_reason_kind
    assert_equal({}, workflow_run.wait_reason_payload)
    assert_nil workflow_run.blocking_resource_type
    assert_nil workflow_run.blocking_resource_id
  end

  test "rechecks retained conversation state before auto resuming a workflow" do
    context = build_waiting_recovery_context!

    AgentProgramVersions::RecordHeartbeat.call(
      deployment: context[:agent_program_version],
      health_status: "healthy",
      health_metadata: {},
      auto_resume_eligible: true
    )

    service = AgentProgramVersions::AutoResumeWorkflows.new(deployment: context[:agent_program_version])
    inject_pending_delete_before_resume!(service, context[:conversation])

    assert_equal [], service.call

    workflow_run = context[:workflow_run].reload
    assert workflow_run.waiting?
    assert_equal "agent_unavailable", workflow_run.wait_reason_kind
    assert_equal context[:agent_program_version].public_id, workflow_run.blocking_resource_id
  end

  private

  def build_waiting_recovery_context!
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    richer_snapshot = create_capability_snapshot!(
      agent_program_version: context[:agent_program_version],
      version: 2,
      protocol_methods: default_protocol_methods("agent_health", "capabilities_handshake", "conversation_transcript_list"),
      tool_catalog: default_tool_catalog("exec_command", "workspace_variables_get"),
      config_schema_snapshot: default_config_schema_snapshot(include_selector_slots: true),
      default_config_snapshot: default_default_config_snapshot(include_selector_slots: true)
    )
    adopt_agent_program_version!(context, richer_snapshot, turn: nil)
    context[:agent_session].update!(auto_resume_eligible: true)
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      agent_program: context[:agent_program]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Recovery input",
      executor_program: context[:executor_program],
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
      severity: "transient",
      reason: "heartbeat_missed",
      occurred_at: Time.current
    )

    context.merge(conversation: conversation, turn: turn.reload, workflow_run: workflow_run.reload)
  end

  def build_waiting_human_interaction_recovery_context!
    context = build_human_interaction_context!
    context[:agent_session].update!(auto_resume_eligible: true)
    request = HumanInteractions::Request.call(
      request_type: "HumanTaskRequest",
      workflow_node: context[:workflow_node],
      blocking: true,
      request_payload: { "instructions" => "Need operator input" }
    )

    AgentProgramVersions::MarkUnavailable.call(
      deployment: context[:agent_program_version],
      severity: "transient",
      reason: "heartbeat_missed",
      occurred_at: Time.current
    )

    context.merge(request: request, workflow_run: context[:workflow_run].reload)
  end

  def create_compatible_replacement_deployment!(
    installation:,
    agent_program:,
    executor_program: create_executor_program!(installation: installation)
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
    agent_program.update!(default_executor_program: executor_program)
    AgentSession.where(agent_program: agent_program, lifecycle_state: "active").update_all(
      lifecycle_state: "stale",
      updated_at: Time.current
    )
    create_agent_session!(
      installation: installation,
      agent_program: agent_program,
      agent_program_version: deployment,
      health_status: "offline",
      auto_resume_eligible: true,
      last_heartbeat_at: Time.current,
      last_health_check_at: Time.current
    )
    ExecutorSession.where(executor_program: executor_program, lifecycle_state: "active").update_all(
      lifecycle_state: "stale",
      updated_at: Time.current
    )
    create_executor_session!(
      installation: installation,
      executor_program: executor_program,
      last_heartbeat_at: Time.current
    )
    deployment
  end

  def inject_pending_delete_before_resume!(service, conversation)
    injected = false

    service.singleton_class.prepend(Module.new do
      define_method(:resume_workflow!) do |*args|
        unless injected
          injected = true
          conversation.update!(deletion_state: "pending_delete", deleted_at: Time.current)
        end

        super(*args)
      end
    end)
  end
end
