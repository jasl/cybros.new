require "test_helper"

class AgentTaskRunTest < ActiveSupport::TestCase
  test "requires workflow ownership to stay aligned with the accepted agent connection" do
    context = build_agent_control_context!
    agent_task_run = create_agent_task_run!(workflow_node: context[:workflow_node])

    assert agent_task_run.valid?

    foreign_installation = Installation.new(
      name: "Foreign Installation #{next_test_sequence}",
      bootstrap_state: "bootstrapped",
      global_settings: {}
    )
    foreign_installation.save!(validate: false)
    foreign_agent = create_agent!(installation: foreign_installation)
    foreign_agent_definition_version = create_agent_definition_version!(
      installation: foreign_installation,
      agent: foreign_agent
    )
    foreign_agent_connection = create_agent_connection!(
      installation: foreign_installation,
      agent: foreign_agent,
      agent_definition_version: foreign_agent_definition_version
    )

    agent_task_run.holder_agent_connection = foreign_agent_connection

    assert_not agent_task_run.valid?
    assert_includes agent_task_run.errors[:holder_agent_connection], "must belong to the same installation"
  end

  test "enforces close lifecycle pairings" do
    context = build_agent_control_context!
    agent_task_run = create_agent_task_run!(workflow_node: context[:workflow_node])

    agent_task_run.assign_attributes(
      close_state: "requested",
      close_reason_kind: "turn_interrupt"
    )

    assert_not agent_task_run.valid?
    assert_includes agent_task_run.errors[:close_requested_at], "must exist when close has been requested"

    agent_task_run.assign_attributes(
      close_requested_at: Time.current,
      close_grace_deadline_at: 30.seconds.from_now,
      close_force_deadline_at: 60.seconds.from_now,
      close_state: "closed",
      close_acknowledged_at: Time.current,
      close_outcome_kind: "graceful"
    )

    assert agent_task_run.valid?
  end

  test "supports subagent connection and origin turn references" do
    assert_includes AgentTaskRun.column_names, "subagent_connection_id"
    assert_includes AgentTaskRun.column_names, "origin_turn_id"
    assert_includes AgentTaskRun.column_names, "kind"

    subagent_connection_association = AgentTaskRun.reflect_on_association(:subagent_connection)
    origin_turn_association = AgentTaskRun.reflect_on_association(:origin_turn)

    assert_equal :belongs_to, subagent_connection_association&.macro
    assert_equal :belongs_to, origin_turn_association&.macro

    context = build_agent_control_context!
    owner_conversation = context[:conversation]
    child_conversation = create_conversation_record!(
      workspace: context[:workspace],
      parent_conversation: owner_conversation,
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version],
      kind: "fork",
      addressability: "agent_addressable"
    )
    subagent_connection = SubagentConnection.create!(
      installation: context[:installation],
      owner_conversation: owner_conversation,
      conversation: child_conversation,
      user: owner_conversation.user,
      workspace: owner_conversation.workspace,
      agent: owner_conversation.agent,
      origin_turn: context[:turn],
      scope: "turn",
      profile_key: "worker",
      depth: 0
    )

    agent_task_run = create_agent_task_run!(
      workflow_node: context[:workflow_node],
      kind: "subagent_step",
      subagent_connection: subagent_connection,
      origin_turn: context[:turn]
    )

    assert_equal subagent_connection, agent_task_run.subagent_connection
    assert_equal context[:turn], agent_task_run.origin_turn
  end

  test "derives feature policy from the turn instead of storing a duplicate snapshot" do
    context = build_agent_control_context!
    agent_task_run = create_agent_task_run!(workflow_node: context[:workflow_node])

    refute_includes AgentTaskRun.column_names, "feature_policy_snapshot"
    assert_equal context[:turn].feature_policy_snapshot, agent_task_run.feature_policy_snapshot
  end

  test "validates supervision state fields and requires progress timestamps once supervision has started" do
    context = build_agent_control_context!

    assert_includes AgentTaskRun.column_names, "supervision_state"
    assert_includes AgentTaskRun.column_names, "focus_kind"
    assert_includes AgentTaskRun.column_names, "request_summary"
    assert_includes AgentTaskRun.column_names, "current_focus_summary"
    assert_includes AgentTaskRun.column_names, "recent_progress_summary"
    assert_includes AgentTaskRun.column_names, "waiting_summary"
    assert_includes AgentTaskRun.column_names, "blocked_summary"
    assert_includes AgentTaskRun.column_names, "next_step_hint"
    assert_includes AgentTaskRun.column_names, "last_progress_at"
    assert_includes AgentTaskRun.column_names, "supervision_sequence"
    assert_includes AgentTaskRun.column_names, "supervision_payload"

    queued_task = create_agent_task_run!(workflow_node: context[:workflow_node])
    assert queued_task.valid?

    running_task = AgentTaskRun.new(
      create_agent_task_run!(workflow_node: context[:workflow_node]).attributes.slice(
        "installation_id",
        "user_id",
        "workspace_id",
        "agent_id",
        "workflow_run_id",
        "workflow_node_id",
        "conversation_id",
        "turn_id",
        "execution_runtime_id",
        "kind",
        "logical_work_id",
        "attempt_no",
        "task_payload",
        "progress_payload",
        "terminal_payload",
        "close_state",
        "close_outcome_payload"
      ).merge(
        "lifecycle_state" => "running",
        "started_at" => Time.current,
        "supervision_state" => "running",
        "focus_kind" => "implementation",
        "request_summary" => "Refactor supervision status",
        "current_focus_summary" => "Adding user-facing rollout fields",
        "recent_progress_summary" => "Reviewed the runtime models",
        "waiting_summary" => nil,
        "blocked_summary" => nil,
        "next_step_hint" => "Wire in the shared concern",
        "supervision_payload" => {}
      )
    )

    assert_not running_task.valid?
    assert_includes running_task.errors[:last_progress_at], "must exist when supervision has started"

    running_task.last_progress_at = Time.current
    assert running_task.valid?

    running_task.focus_kind = "unsupported"
    assert_not running_task.valid?
    assert_includes running_task.errors[:focus_kind], "is not included in the list"

    running_task.focus_kind = "implementation"
    running_task.request_summary = "x" * 256
    assert_not running_task.valid?
    assert_includes running_task.errors[:request_summary], "is too long (maximum is 255 characters)"
  end

  test "advances the supervision sequence when semantic progress changes" do
    context = build_agent_control_context!
    agent_task_run = create_agent_task_run!(
      workflow_node: context[:workflow_node],
      supervision_state: "queued",
      focus_kind: "general",
      supervision_sequence: 0,
      supervision_payload: {}
    )

    assert_equal 0, agent_task_run.supervision_sequence

    agent_task_run.advance_supervision_sequence!

    assert_equal 1, agent_task_run.reload.supervision_sequence
    assert agent_task_run.last_progress_at.present?
  end

  test "requires duplicated owner context to match the workflow run and conversation" do
    context = build_agent_control_context!
    foreign = create_workspace_context!

    agent_task_run = AgentTaskRun.new(
      installation: context[:installation],
      workflow_run: context[:workflow_run],
      workflow_node: context[:workflow_node],
      conversation: context[:conversation],
      turn: context[:turn],
      agent: context[:agent],
      user_id: foreign[:user].id,
      workspace_id: foreign[:workspace].id,
      execution_runtime_id: foreign[:execution_runtime].id,
      kind: "turn_step",
      lifecycle_state: "queued",
      logical_work_id: "owner-context-mismatch",
      attempt_no: 1,
      task_payload: {},
      progress_payload: {},
      terminal_payload: {},
      close_outcome_payload: {}
    )

    assert_not agent_task_run.valid?
    assert_includes agent_task_run.errors[:user], "must match the workflow run user"
    assert_includes agent_task_run.errors[:workspace], "must match the workflow run workspace"
    assert_includes agent_task_run.errors[:execution_runtime], "must match the workflow run execution runtime"
  end
end
