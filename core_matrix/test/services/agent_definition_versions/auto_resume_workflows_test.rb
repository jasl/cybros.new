require "test_helper"

class AgentDefinitionVersions::AutoResumeWorkflowsTest < ActiveSupport::TestCase
  test "automatically resumes waiting workflows when runtime identity did not drift" do
    context = build_waiting_recovery_context!
    assert_equal context[:agent_definition_version].public_id, context[:workflow_run].reload.blocking_resource_id

    AgentConnections::RecordHeartbeat.call(
      agent_definition_version: context[:agent_definition_version],
      health_status: "healthy",
      health_metadata: {},
      auto_resume_eligible: true
    )

    resumed = AgentDefinitionVersions::AutoResumeWorkflows.call(agent_definition_version: context[:agent_definition_version])

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
    drifted_snapshot = create_compatible_agent_definition_version!(
      agent_definition_version: context[:agent_definition_version],
      version: 3,
      protocol_methods: default_protocol_methods("agent_health", "capabilities_handshake", "conversation_transcript_list"),
      tool_contract: default_tool_catalog("exec_command"),
      default_canonical_config: {
        "sandbox" => "workspace-read",
      }
    )
    adopt_agent_definition_version!(context, drifted_snapshot, turn: nil)

    AgentConnections::RecordHeartbeat.call(
      agent_definition_version: context[:agent_definition_version],
      health_status: "healthy",
      health_metadata: {},
      auto_resume_eligible: true
    )

    resumed = AgentDefinitionVersions::AutoResumeWorkflows.call(agent_definition_version: context[:agent_definition_version])

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

    AgentConnections::RecordHeartbeat.call(
      agent_definition_version: context[:agent_definition_version],
      health_status: "healthy",
      health_metadata: {},
      auto_resume_eligible: true
    )

    assert_equal [], AgentDefinitionVersions::AutoResumeWorkflows.call(agent_definition_version: context[:agent_definition_version])
    assert context[:workflow_run].reload.waiting?
  end

  test "compatible rotated agent_definition_version auto resumes waiting workflows and rewrites turn pinning" do
    context = build_waiting_recovery_context!
    replacement = create_compatible_replacement_agent_definition_version!(
      installation: context[:installation],
      agent: context[:agent],
      execution_runtime: context[:execution_runtime]
    )

    AgentConnections::RecordHeartbeat.call(
      agent_definition_version: replacement,
      health_status: "healthy",
      health_metadata: { "release" => "fenix-0.2.0" },
      auto_resume_eligible: true
    )

    resumed = AgentDefinitionVersions::AutoResumeWorkflows.call(agent_definition_version: replacement)

    assert_equal [context[:workflow_run].id], resumed.map(&:id)
    assert_equal context[:agent], context[:conversation].reload.agent
    turn = context[:turn].reload
    assert_equal replacement, turn.agent_definition_version
    assert_equal replacement.fingerprint, turn.pinned_agent_definition_fingerprint
    assert_equal replacement.public_id, turn.execution_snapshot.identity["agent_definition_version_id"]
    assert context[:workflow_run].reload.ready?
  end

  test "compatible rotated agent_definition_version auto resumes through the canonical rebinding owner" do
    context = build_waiting_recovery_context!
    replacement = create_compatible_replacement_agent_definition_version!(
      installation: context[:installation],
      agent: context[:agent],
      execution_runtime: context[:execution_runtime]
    )
    original_rebind_call = nil
    rebind_calls = []

    AgentConnections::RecordHeartbeat.call(
      agent_definition_version: replacement,
      health_status: "healthy",
      health_metadata: { "release" => "fenix-0.2.0" },
      auto_resume_eligible: true
    )

    original_rebind_call = ExecutionIdentityRecovery::RebindTurn.method(:call)
    ExecutionIdentityRecovery::RebindTurn.singleton_class.define_method(:call) do |*args, **kwargs|
      rebind_calls << kwargs
      original_rebind_call.call(*args, **kwargs)
    end

    resumed = AgentDefinitionVersions::AutoResumeWorkflows.call(agent_definition_version: replacement)

    assert_equal [context[:workflow_run].id], resumed.map(&:id)
    assert_equal 1, rebind_calls.size
    assert_equal context[:turn].id, rebind_calls.first.fetch(:turn).id
    assert_equal replacement, rebind_calls.first.fetch(:recovery_target).agent_definition_version
  ensure
    if original_rebind_call
      ExecutionIdentityRecovery::RebindTurn.singleton_class.define_method(:call, original_rebind_call)
    end
  end

  test "cross environment rotated deployments require manual recovery instead of auto resume" do
    context = build_waiting_recovery_context!
    replacement = create_compatible_replacement_agent_definition_version!(
      installation: context[:installation],
      agent: context[:agent]
    )

    AgentConnections::RecordHeartbeat.call(
      agent_definition_version: replacement,
      health_status: "healthy",
      health_metadata: { "release" => "fenix-0.2.0" },
      auto_resume_eligible: true
    )

    resumed = AgentDefinitionVersions::AutoResumeWorkflows.call(agent_definition_version: replacement)

    assert_equal [], resumed
    assert_equal context[:agent], context[:conversation].reload.agent
    assert_equal context[:agent_definition_version], context[:turn].reload.agent_definition_version
    assert_equal "manual_recovery_required", context[:workflow_run].reload.wait_reason_kind
    assert_equal "execution_runtime_drift", context[:workflow_run].recovery_drift_reason
  end

  test "restores the original human-interaction blocker after auto resume" do
    context = build_waiting_human_interaction_recovery_context!

    AgentConnections::RecordHeartbeat.call(
      agent_definition_version: context[:agent_definition_version],
      health_status: "healthy",
      health_metadata: {},
      auto_resume_eligible: true
    )

    resumed = AgentDefinitionVersions::AutoResumeWorkflows.call(agent_definition_version: context[:agent_definition_version])

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

    AgentConnections::RecordHeartbeat.call(
      agent_definition_version: context[:agent_definition_version],
      health_status: "healthy",
      health_metadata: {},
      auto_resume_eligible: true
    )

    resumed = AgentDefinitionVersions::AutoResumeWorkflows.call(agent_definition_version: context[:agent_definition_version])

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

    AgentConnections::RecordHeartbeat.call(
      agent_definition_version: context[:agent_definition_version],
      health_status: "healthy",
      health_metadata: {},
      auto_resume_eligible: true
    )

    service = AgentDefinitionVersions::AutoResumeWorkflows.new(agent_definition_version: context[:agent_definition_version])
    inject_pending_delete_before_resume!(service, context[:conversation])

    assert_equal [], service.call

    workflow_run = context[:workflow_run].reload
    assert workflow_run.waiting?
    assert_equal "agent_unavailable", workflow_run.wait_reason_kind
    assert_equal context[:agent_definition_version].public_id, workflow_run.blocking_resource_id
  end

  test "reuses one active agent connection lookup for resumable-state checks" do
    context = build_waiting_recovery_context!

    AgentConnections::RecordHeartbeat.call(
      agent_definition_version: context[:agent_definition_version],
      health_status: "healthy",
      health_metadata: {},
      auto_resume_eligible: true
    )

    service = AgentDefinitionVersions::AutoResumeWorkflows.new(
      agent_definition_version: context[:agent_definition_version]
    )

    queries = capture_sql_queries do
      2.times do
        service.send(:resumable_agent_definition_version_state?)
        service.send(:scheduling_ready?)
      end
    end

    agent_connection_queries = queries.count { |sql| sql.include?("\"agent_connections\"") }

    assert_operator agent_connection_queries, :<=, 1,
      "Expected active agent connection lookup to be cached, got #{agent_connection_queries} agent_connection queries:\n#{queries.join("\n")}"
  end

  private

  def build_waiting_recovery_context!
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    richer_snapshot = create_compatible_agent_definition_version!(
      agent_definition_version: context[:agent_definition_version],
      version: 2,
      protocol_methods: default_protocol_methods("agent_health", "capabilities_handshake", "conversation_transcript_list"),
      tool_contract: default_tool_catalog("exec_command", "workspace_variables_get"),
      canonical_config_schema: default_canonical_config_schema(include_selector_slots: true),
      default_canonical_config: default_default_canonical_config(include_selector_slots: true)
    )
    adopt_agent_definition_version!(context, richer_snapshot, turn: nil)
    context[:agent_connection].update!(auto_resume_eligible: true)
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      agent: context[:agent]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Recovery input",
      execution_runtime: context[:execution_runtime],
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

    AgentDefinitionVersions::MarkUnavailable.call(
      agent_definition_version: context[:agent_definition_version],
      severity: "transient",
      reason: "heartbeat_missed",
      occurred_at: Time.current
    )

    context.merge(conversation: conversation, turn: turn.reload, workflow_run: workflow_run.reload)
  end

  def build_waiting_human_interaction_recovery_context!
    context = build_human_interaction_context!
    context[:agent_connection].update!(auto_resume_eligible: true)
    request = HumanInteractions::Request.call(
      request_type: "HumanTaskRequest",
      workflow_node: context[:workflow_node],
      blocking: true,
      request_payload: { "instructions" => "Need operator input" }
    )

    AgentDefinitionVersions::MarkUnavailable.call(
      agent_definition_version: context[:agent_definition_version],
      severity: "transient",
      reason: "heartbeat_missed",
      occurred_at: Time.current
    )

    context.merge(request: request, workflow_run: context[:workflow_run].reload)
  end

  def create_compatible_replacement_agent_definition_version!(
    installation:,
    agent:,
    execution_runtime: create_execution_runtime!(installation: installation)
  )
    agent_definition_version = create_agent_definition_version!(
      installation: installation,
      agent: agent,
      fingerprint: "replacement-#{next_test_sequence}",
      protocol_methods: default_protocol_methods("agent_health", "capabilities_handshake", "conversation_transcript_list"),
      tool_contract: default_tool_catalog("exec_command", "workspace_variables_get"),
      canonical_config_schema: default_canonical_config_schema(include_selector_slots: true),
      default_canonical_config: default_default_canonical_config(include_selector_slots: true)
    )
    agent.update!(default_execution_runtime: execution_runtime)
    AgentConnection.where(agent: agent, lifecycle_state: "active").update_all(
      lifecycle_state: "stale",
      updated_at: Time.current
    )
    create_agent_connection!(
      installation: installation,
      agent: agent,
      agent_definition_version: agent_definition_version,
      health_status: "offline",
      auto_resume_eligible: true,
      last_heartbeat_at: Time.current,
      last_health_check_at: Time.current
    )
    ExecutionRuntimeConnection.where(execution_runtime: execution_runtime, lifecycle_state: "active").update_all(
      lifecycle_state: "stale",
      updated_at: Time.current
    )
    create_execution_runtime_connection!(
      installation: installation,
      execution_runtime: execution_runtime,
      last_heartbeat_at: Time.current
    )
    agent_definition_version
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
