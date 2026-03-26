require "test_helper"

class AgentTaskRunTest < ActiveSupport::TestCase
  test "requires workflow ownership to stay aligned with the accepted deployment" do
    context = build_agent_control_context!
    agent_task_run = create_agent_task_run!(workflow_node: context[:workflow_node])

    assert agent_task_run.valid?

    foreign_installation = Installation.new(
      name: "Foreign Installation #{next_test_sequence}",
      bootstrap_state: "bootstrapped",
      global_settings: {}
    )
    foreign_installation.save!(validate: false)
    foreign_agent_installation = create_agent_installation!(installation: foreign_installation)
    foreign_environment = create_execution_environment!(installation: foreign_installation)
    foreign_deployment = create_agent_deployment!(
      installation: foreign_installation,
      agent_installation: foreign_agent_installation,
      execution_environment: foreign_environment
    )

    agent_task_run.holder_agent_deployment = foreign_deployment

    assert_not agent_task_run.valid?
    assert_includes agent_task_run.errors[:holder_agent_deployment], "must belong to the same installation"
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
end
