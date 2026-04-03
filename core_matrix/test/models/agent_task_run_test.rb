require "test_helper"

class AgentTaskRunTest < ActiveSupport::TestCase
  test "requires workflow ownership to stay aligned with the accepted agent session" do
    context = build_agent_control_context!
    agent_task_run = create_agent_task_run!(workflow_node: context[:workflow_node])

    assert agent_task_run.valid?

    foreign_installation = Installation.new(
      name: "Foreign Installation #{next_test_sequence}",
      bootstrap_state: "bootstrapped",
      global_settings: {}
    )
    foreign_installation.save!(validate: false)
    foreign_agent_program = create_agent_program!(installation: foreign_installation)
    foreign_deployment = create_agent_program_version!(
      installation: foreign_installation,
      agent_program: foreign_agent_program
    )
    foreign_agent_session = create_agent_session!(
      installation: foreign_installation,
      agent_program: foreign_agent_program,
      agent_program_version: foreign_deployment
    )

    agent_task_run.holder_agent_session = foreign_agent_session

    assert_not agent_task_run.valid?
    assert_includes agent_task_run.errors[:holder_agent_session], "must belong to the same installation"
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

  test "supports subagent session and origin turn references" do
    assert_includes AgentTaskRun.column_names, "subagent_session_id"
    assert_includes AgentTaskRun.column_names, "origin_turn_id"
    assert_includes AgentTaskRun.column_names, "kind"

    subagent_session_association = AgentTaskRun.reflect_on_association(:subagent_session)
    origin_turn_association = AgentTaskRun.reflect_on_association(:origin_turn)

    assert_equal :belongs_to, subagent_session_association&.macro
    assert_equal :belongs_to, origin_turn_association&.macro

    context = build_agent_control_context!
    owner_conversation = context[:conversation]
    child_conversation = create_conversation_record!(
      workspace: context[:workspace],
      parent_conversation: owner_conversation,
      execution_runtime: context[:execution_runtime],
      agent_program_version: context[:agent_program_version],
      kind: "fork",
      addressability: "agent_addressable"
    )
    subagent_session = SubagentSession.create!(
      installation: context[:installation],
      owner_conversation: owner_conversation,
      conversation: child_conversation,
      origin_turn: context[:turn],
      scope: "turn",
      profile_key: "worker",
      depth: 0
    )

    agent_task_run = create_agent_task_run!(
      workflow_node: context[:workflow_node],
      kind: "subagent_step",
      subagent_session: subagent_session,
      origin_turn: context[:turn]
    )

    assert_equal subagent_session, agent_task_run.subagent_session
    assert_equal context[:turn], agent_task_run.origin_turn
  end
end
