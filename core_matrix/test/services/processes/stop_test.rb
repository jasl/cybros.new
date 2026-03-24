require "test_helper"

class Processes::StopTest < ActiveSupport::TestCase
  test "stops a running background service and appends a status event" do
    process_context = build_process_context!
    process_run = Processes::Start.call(
      workflow_node: process_context[:workflow_node],
      execution_environment: process_context[:execution_environment],
      kind: "background_service",
      command_line: "bin/dev",
      origin_message: process_context[:origin_message]
    )

    stopped = Processes::Stop.call(process_run: process_run, reason: "manual_stop")

    assert stopped.stopped?
    assert_not_nil stopped.ended_at
    assert_equal "manual_stop", stopped.metadata["stop_reason"]

    last_event = WorkflowNodeEvent.where(workflow_node: process_context[:workflow_node]).order(:ordinal).last
    assert_equal "status", last_event.event_kind
    assert_equal "stopped", last_event.payload["state"]
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
    workflow_node = create_workflow_node!(workflow_run: workflow_run, metadata: {})

    {
      conversation: conversation,
      execution_environment: context[:execution_environment],
      origin_message: turn.selected_input_message,
      turn: turn,
      workflow_node: workflow_node,
    }.merge(context)
  end
end
