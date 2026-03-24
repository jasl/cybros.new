require "test_helper"

class ProcessRunTest < ActiveSupport::TestCase
  test "requires bounded timeout for turn commands and forbids timeout for background services" do
    process_context = build_process_context!

    command = ProcessRun.new(
      installation: process_context[:installation],
      workflow_node: process_context[:workflow_node],
      execution_environment: process_context[:execution_environment],
      conversation: process_context[:conversation],
      turn: process_context[:turn],
      kind: "turn_command",
      lifecycle_state: "running",
      command_line: "echo hi",
      timeout_seconds: 30,
      metadata: {}
    )
    background_service = ProcessRun.new(
      installation: process_context[:installation],
      workflow_node: process_context[:workflow_node],
      execution_environment: process_context[:execution_environment],
      conversation: process_context[:conversation],
      turn: process_context[:turn],
      origin_message: process_context[:origin_message],
      kind: "background_service",
      lifecycle_state: "running",
      command_line: "bin/dev",
      metadata: {}
    )

    assert command.valid?
    assert background_service.valid?

    missing_timeout = command.dup
    missing_timeout.timeout_seconds = nil
    assert_not missing_timeout.valid?
    assert_includes missing_timeout.errors[:timeout_seconds], "must exist for turn_command process runs"

    forbidden_timeout = background_service.dup
    forbidden_timeout.timeout_seconds = 30
    assert_not forbidden_timeout.valid?
    assert_includes forbidden_timeout.errors[:timeout_seconds], "must be blank for background_service process runs"
  end

  test "keeps redundant conversation and turn ownership aligned with the workflow node" do
    process_context = build_process_context!

    process_run = ProcessRun.new(
      installation: process_context[:installation],
      workflow_node: process_context[:workflow_node],
      execution_environment: process_context[:execution_environment],
      conversation: process_context[:conversation],
      turn: process_context[:turn],
      origin_message: process_context[:origin_message],
      kind: "turn_command",
      lifecycle_state: "running",
      command_line: "echo hi",
      timeout_seconds: 30,
      metadata: {}
    )

    assert process_run.valid?
    assert_equal process_context[:conversation], process_run.conversation
    assert_equal process_context[:turn], process_run.turn
    assert_equal process_context[:origin_message], process_run.origin_message

    mismatched_turn = Turns::StartUserTurn.call(
      conversation: process_context[:conversation],
      content: "Different turn",
      agent_deployment: process_context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    process_run.turn = mismatched_turn

    assert_not process_run.valid?
    assert_includes process_run.errors[:turn], "must match the workflow run turn"
  end

  private

  def build_process_context!
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Process input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    workflow_run = create_workflow_run!(turn: turn)
    workflow_node = create_workflow_node!(workflow_run: workflow_run, metadata: { "policy_sensitive" => true })

    {
      conversation: conversation,
      execution_environment: context[:execution_environment],
      origin_message: turn.selected_input_message,
      turn: turn,
      workflow_node: workflow_node,
      agent_deployment: context[:agent_deployment],
    }.merge(context)
  end
end
