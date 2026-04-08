require "test_helper"

class Workflows::ManualResumeTest < ActiveSupport::TestCase
  test "resumes a paused workflow on a compatible replacement deployment with a one time override" do
    context = build_paused_recovery_context!
    replacement = create_compatible_replacement_deployment!(
      installation: context[:installation],
      agent_program: context[:agent_program],
      executor_program: context[:executor_program],
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
    assert_equal replacement, resumed.turn.reload.agent_program_version
    assert_equal replacement.fingerprint, resumed.turn.pinned_program_version_fingerprint
    assert_equal "role:planner", resumed.turn.normalized_selector
    assert_equal "openai", resumed.turn.resolved_provider_handle
    assert_equal "gpt-5.4", resumed.turn.resolved_model_ref
    assert_equal replacement.public_id, resumed.execution_identity["agent_program_version_id"]

    conversation = context[:conversation].reload
    assert_equal context[:agent_program], conversation.agent_program
    assert_equal "auto", conversation.interactive_selector_mode
    assert_nil conversation.interactive_selector_provider_handle
    assert_nil conversation.interactive_selector_model_ref
    assert_equal(
      default_default_config_snapshot(include_selector_slots: true),
      replacement.default_config_snapshot
    )

    audit_log = AuditLog.find_by!(action: "workflow.manual_resumed")
    assert_equal actor, audit_log.actor
    assert_equal resumed, audit_log.subject
    assert_equal replacement.id, audit_log.metadata["deployment_id"]
    assert_equal "role:planner", audit_log.metadata["temporary_selector_override"]
  end

  test "rejects manual resume when the replacement deployment belongs to a different logical agent" do
    context = build_paused_recovery_context!
    other_installation = create_agent_program!(installation: context[:installation])
    replacement = create_compatible_replacement_deployment!(
      installation: context[:installation],
      agent_program: other_installation,
      executor_program: context[:executor_program]
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Workflows::ManualResume.call(
        workflow_run: context[:workflow_run],
        deployment: replacement,
        actor: create_user!(installation: context[:installation], role: "admin")
      )
    end

    assert_includes error.record.errors[:agent_program_version], "must belong to the same agent program"
  end

  test "rejects manual resume when required capabilities are no longer available" do
    context = build_paused_recovery_context!
    replacement = create_compatible_replacement_deployment!(
      installation: context[:installation],
      agent_program: context[:agent_program],
      executor_program: context[:executor_program],
      protocol_methods: default_protocol_methods("agent_health"),
      tool_catalog: default_tool_catalog("exec_command")
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Workflows::ManualResume.call(
        workflow_run: context[:workflow_run],
        deployment: replacement,
        actor: create_user!(installation: context[:installation], role: "admin")
      )
    end

    assert_includes error.record.errors[:agent_program_version], "must preserve the paused workflow capability contract"
  end

  test "rejects manual resume when the frozen selector can no longer be resolved" do
    context = build_paused_recovery_context!
    replacement = create_compatible_replacement_deployment!(
      installation: context[:installation],
      agent_program: context[:agent_program],
      executor_program: context[:executor_program]
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
        deployment: context[:agent_program_version],
        actor: create_user!(installation: context[:installation], role: "admin")
      )
    end

    assert_includes error.record.errors[:deletion_state], "must be retained before manual recovery"
  end

  test "rejects manual resume for archived conversations" do
    context = build_paused_recovery_context!
    context[:conversation].update!(lifecycle_state: "archived")

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Workflows::ManualResume.call(
        workflow_run: context[:workflow_run],
        deployment: context[:agent_program_version],
        actor: create_user!(installation: context[:installation], role: "admin")
      )
    end

    assert_includes error.record.errors[:lifecycle_state], "must be active before manual recovery"
  end

  test "rejects manual resume while close is in progress" do
    context = build_paused_recovery_context!
    ConversationCloseOperation.create!(
      installation: context[:conversation].installation,
      conversation: context[:conversation],
      intent_kind: "archive",
      lifecycle_state: "requested",
      requested_at: Time.current,
      summary_payload: {}
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Workflows::ManualResume.call(
        workflow_run: context[:workflow_run],
        deployment: context[:agent_program_version],
        actor: create_user!(installation: context[:installation], role: "admin")
      )
    end

    assert_includes error.record.errors[:base], "must not resume paused work while close is in progress"
  end

  test "uses blocker snapshot semantics while validating paused recovery" do
    context = build_paused_recovery_context!
    actor = create_user!(installation: context[:installation], role: "admin")
    fake_snapshot = ConversationBlockerSnapshot.new(
      retained: true,
      active: true,
      closing: true
    )
    original_call = Conversations::BlockerSnapshotQuery.method(:call)
    Conversations::BlockerSnapshotQuery.singleton_class.define_method(:call) do |*args, **kwargs|
      fake_snapshot
    end

    begin
      error = assert_raises(ActiveRecord::RecordInvalid) do
        Workflows::ManualResume.call(
          workflow_run: context[:workflow_run],
          deployment: context[:agent_program_version],
          actor: actor
        )
      end

      assert_includes error.record.errors[:base], "must not resume paused work while close is in progress"
    ensure
      Conversations::BlockerSnapshotQuery.singleton_class.define_method(:call, original_call)
    end
  end

  test "rejects manual resume when the replacement deployment belongs to another execution environment" do
    context = build_paused_recovery_context!
    replacement = create_compatible_replacement_deployment!(
      installation: context[:installation],
      agent_program: context[:agent_program]
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Workflows::ManualResume.call(
        workflow_run: context[:workflow_run],
        deployment: replacement,
        actor: create_user!(installation: context[:installation], role: "admin")
      )
    end

    assert_includes error.record.errors[:agent_program_version], "must preserve the frozen executor program"
  end

  test "rechecks paused recovery state after acquiring the conversation lock" do
    context = build_paused_recovery_context!
    replacement = create_compatible_replacement_deployment!(
      installation: context[:installation],
      agent_program: context[:agent_program],
      executor_program: context[:executor_program]
    )
    service = Workflows::ManualResume.new(
      workflow_run: context[:workflow_run],
      deployment: replacement,
      actor: create_user!(installation: context[:installation], role: "admin")
    )
    inject_ready_state_after_initial_check!(service, context[:workflow_run])

    error = assert_raises(ActiveRecord::RecordInvalid) do
      service.call
    end

    assert_includes error.record.errors[:wait_reason_kind], "must require manual recovery before resuming"
    assert context[:workflow_run].reload.ready?
    assert_equal context[:agent_program], context[:conversation].reload.agent_program
    assert_equal context[:agent_program_version], context[:turn].reload.agent_program_version
  end

  test "manual resume restores the original human-interaction blocker for paused workflows" do
    context = build_paused_human_interaction_recovery_context!
    replacement = create_compatible_replacement_deployment!(
      installation: context[:installation],
      agent_program: context[:agent_program],
      executor_program: context[:executor_program],
      selector_snapshot: default_default_config_snapshot(include_selector_slots: true)
    )
    actor = create_user!(installation: context[:installation], role: "admin")

    resumed = Workflows::ManualResume.call(
      workflow_run: context[:workflow_run],
      deployment: replacement,
      actor: actor
    )

    assert resumed.waiting?
    assert_equal "human_interaction", resumed.wait_reason_kind
    assert_equal "HumanInteractionRequest", resumed.blocking_resource_type
    assert_equal context[:request].public_id, resumed.blocking_resource_id
    assert_equal replacement, resumed.turn.reload.agent_program_version
  end

  test "manual resume restores the original subagent barrier blocker for paused workflows" do
    context = build_paused_subagent_barrier_recovery_context!
    replacement = create_compatible_replacement_deployment!(
      installation: context[:installation],
      agent_program: context[:agent_program],
      executor_program: context[:executor_program],
      selector_snapshot: default_default_config_snapshot(include_selector_slots: true)
    )
    actor = create_user!(installation: context[:installation], role: "admin")

    resumed = Workflows::ManualResume.call(
      workflow_run: context[:workflow_run],
      deployment: replacement,
      actor: actor
    )

    assert resumed.waiting?
    assert_equal "subagent_barrier", resumed.wait_reason_kind
    assert_equal "SubagentBarrier", resumed.blocking_resource_type
    assert_equal context[:blocking_resource_id], resumed.blocking_resource_id
    assert_equal({}, resumed.wait_reason_payload)
    assert_equal replacement, resumed.turn.reload.agent_program_version
  end

  test "manual resume uses the same turn rebinding owner as recovery-plan application" do
    context = build_paused_recovery_context!
    replacement = create_compatible_replacement_deployment!(
      installation: context[:installation],
      agent_program: context[:agent_program],
      executor_program: context[:executor_program],
      selector_snapshot: default_default_config_snapshot(include_selector_slots: true)
    )
    original_rebind_call = nil
    rebind_calls = []

    original_rebind_call = AgentProgramVersions::RebindTurn.method(:call)
    AgentProgramVersions::RebindTurn.singleton_class.define_method(:call) do |*args, **kwargs|
      rebind_calls << kwargs
      original_rebind_call.call(*args, **kwargs)
    end

    resumed = Workflows::ManualResume.call(
      workflow_run: context[:workflow_run],
      deployment: replacement,
      actor: create_user!(installation: context[:installation], role: "admin"),
      selector: "role:planner"
    )

    assert_equal context[:workflow_run].id, resumed.id
    assert_equal 1, rebind_calls.size
    assert_equal context[:turn].id, rebind_calls.first.fetch(:turn).id
    assert_equal replacement, rebind_calls.first.fetch(:recovery_target).agent_program_version
  ensure
    if original_rebind_call
      AgentProgramVersions::RebindTurn.singleton_class.define_method(:call, original_rebind_call)
    end
  end

  private

  def build_paused_recovery_context!
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
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      agent_program: context[:agent_program]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Paused recovery input",
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
      severity: "prolonged",
      reason: "runtime_offline",
      occurred_at: Time.current
    )

    context.merge(conversation: conversation, turn: turn.reload, workflow_run: workflow_run.reload)
  end

  def build_paused_human_interaction_recovery_context!
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
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      agent_program: context[:agent_program]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Human interaction input",
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

    Workflows::Mutate.call(
      workflow_run: workflow_run,
      nodes: [
        {
          node_key: "human_gate",
          node_type: "human_interaction",
          decision_source: "agent_program",
          metadata: {},
        },
      ],
      edges: [
        { from_node_key: "root", to_node_key: "human_gate" },
      ]
    )
    request = HumanInteractions::Request.call(
      request_type: "HumanTaskRequest",
      workflow_node: workflow_run.workflow_nodes.find_by!(node_key: "human_gate"),
      blocking: true,
      request_payload: { "instructions" => "Need operator input" }
    )
    AgentProgramVersions::MarkUnavailable.call(
      deployment: context[:agent_program_version],
      severity: "prolonged",
      reason: "runtime_offline",
      occurred_at: Time.current
    )

    context.merge(
      conversation: conversation,
      turn: turn.reload,
      workflow_run: workflow_run.reload,
      workflow_node: workflow_run.workflow_nodes.find_by!(node_key: "human_gate"),
      request: request
    )
  end

  def build_paused_subagent_barrier_recovery_context!
    context = build_paused_recovery_context!
    child_conversations = 2.times.map do
      create_conversation_record!(
        installation: context[:installation],
        workspace: context[:workspace],
        parent_conversation: context[:conversation],
        kind: "fork",
        executor_program: context[:executor_program],
        agent_program_version: context[:agent_program_version],
        addressability: "agent_addressable"
      )
    end
    sessions = child_conversations.map do |child_conversation|
      SubagentSession.create!(
        installation: context[:installation],
        owner_conversation: context[:conversation],
        conversation: child_conversation,
        origin_turn: context[:turn],
        scope: "conversation",
        profile_key: "researcher",
        depth: 0,
        observed_status: "running"
      )
    end
    blocking_resource_id = "batch-subagents-1:stage:0"

    yielding_node = create_workflow_node!(
      workflow_run: context[:workflow_run],
      node_key: "agent_step_1",
      node_type: "agent_task_run",
      lifecycle_state: "completed",
      started_at: 2.minutes.ago,
      finished_at: 90.seconds.ago
    )

    spawn_nodes = sessions.map.with_index(1) do |session, index|
      create_workflow_node!(
        workflow_run: context[:workflow_run],
        node_key: "subagent_#{index}",
        node_type: "subagent_spawn",
        lifecycle_state: "completed",
        intent_kind: "subagent_spawn",
        intent_batch_id: "batch-subagents-1",
        intent_id: "intent-subagent-#{index}",
        intent_requirement: "required",
        stage_index: 0,
        stage_position: index - 1,
        yielding_workflow_node: yielding_node,
        spawned_subagent_session: session,
        started_at: 80.seconds.ago,
        finished_at: 70.seconds.ago
      )
    end

    WorkflowArtifact.create!(
      installation: context[:installation],
      workflow_run: context[:workflow_run],
      workflow_node: yielding_node,
      artifact_key: blocking_resource_id,
      artifact_kind: "intent_batch_barrier",
      storage_mode: "json_document",
      payload: {
        "batch_id" => "batch-subagents-1",
        "stage" => {
          "stage_index" => 0,
          "dispatch_mode" => "parallel",
          "completion_barrier" => "wait_all",
        },
        "accepted_intent_ids" => spawn_nodes.map(&:intent_id),
        "rejected_intent_ids" => [],
      }
    )

    context[:workflow_run].update!(
      wait_state: "waiting",
      wait_reason_kind: "subagent_barrier",
      wait_reason_payload: {},
      recovery_state: nil,
      recovery_reason: nil,
      recovery_drift_reason: nil,
      recovery_agent_task_run_public_id: nil,
      wait_snapshot_document: nil,
      waiting_since_at: Time.current,
      blocking_resource_type: "SubagentBarrier",
      blocking_resource_id: blocking_resource_id
    )
    AgentProgramVersions::MarkUnavailable.call(
      deployment: context[:agent_program_version],
      severity: "prolonged",
      reason: "runtime_offline",
      occurred_at: Time.current
    )

    context.merge(
      workflow_run: context[:workflow_run].reload,
      subagent_sessions: sessions,
      blocking_resource_id: blocking_resource_id
    )
  end

  def create_compatible_replacement_deployment!(
    installation:,
    agent_program:,
    executor_program: create_executor_program!(installation: installation),
    protocol_methods: default_protocol_methods("agent_health", "capabilities_handshake", "conversation_transcript_list"),
    tool_catalog: default_tool_catalog("exec_command", "workspace_variables_get"),
    selector_snapshot: default_default_config_snapshot(include_selector_slots: true)
  )
    AgentSession.where(agent_program: agent_program, lifecycle_state: "active").update_all(
      lifecycle_state: "stale",
      updated_at: Time.current
    )
    deployment = create_agent_program_version!(
      installation: installation,
      agent_program: agent_program,
      fingerprint: "replacement-#{next_test_sequence}",
      protocol_methods: protocol_methods,
      tool_catalog: tool_catalog,
      config_schema_snapshot: default_config_schema_snapshot(include_selector_slots: true),
      default_config_snapshot: selector_snapshot
    )
    agent_program.update!(default_executor_program: executor_program)
    create_agent_session!(
      installation: installation,
      agent_program: agent_program,
      agent_program_version: deployment,
      health_status: "healthy",
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

  def inject_ready_state_after_initial_check!(service, workflow_run)
    injected = false

    service.singleton_class.prepend(Module.new do
      define_method(:validate_wait_state!) do |current_workflow_run = @workflow_run|
        super(current_workflow_run).tap do
          next if injected

          injected = true
          workflow_run.update!(Workflows::WaitState.ready_attributes)
        end
      end
    end)
  end
end
