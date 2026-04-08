require "test_helper"

class ProcessRunTest < ActiveSupport::TestCase
  test "requires the process run executor program to match the frozen turn executor program" do
    process_context = build_process_context!
    other_runtime = create_executor_program!(
      installation: process_context[:installation],
      executor_fingerprint: "other-host",
      capability_payload: {}
    )

    process_run = ProcessRun.new(
      installation: process_context[:installation],
      workflow_node: process_context[:workflow_node],
      executor_program: other_runtime,
      conversation: process_context[:conversation],
      turn: process_context[:turn],
      origin_message: process_context[:origin_message],
      kind: "background_service",
      lifecycle_state: "running",
      command_line: "echo hi",
      metadata: {}
    )

    assert_not process_run.valid?
    assert_includes process_run.errors[:executor_program], "must match the turn executor program"
  end

  private

  def build_process_context!
    installation = create_installation!
    agent_program = create_agent_program!(installation: installation)
    user = create_user!(installation: installation)
    user_program_binding = create_user_program_binding!(
      installation: installation,
      user: user,
      agent_program: agent_program
    )
    workspace = create_workspace!(
      installation: installation,
      user: user,
      user_program_binding: user_program_binding
    )
    agent_program_version = create_agent_program_version!(installation: installation, agent_program: agent_program)
    executor_program = create_executor_program!(installation: installation)
    conversation = Conversation.create!(
      installation: installation,
      workspace: workspace,
      agent_program: agent_program,
      kind: "root",
      purpose: "interactive",
      lifecycle_state: "active"
    )
    turn = Turn.create!(
      installation: installation,
      conversation: conversation,
      agent_program_version: agent_program_version,
      executor_program: executor_program,
      sequence: 1,
      lifecycle_state: "active",
      origin_kind: "manual_user",
      origin_payload: {},
      pinned_program_version_fingerprint: agent_program_version.fingerprint,
      feature_policy_snapshot: conversation.feature_policy_snapshot,
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    workflow_run = create_workflow_run!(turn: turn)
    workflow_node = create_workflow_node!(workflow_run: workflow_run, metadata: { "policy_sensitive" => true })

    {
      installation: installation,
      conversation: conversation,
      executor_program: executor_program,
      origin_message: nil,
      turn: turn,
      workflow_node: workflow_node,
    }
  end
end
