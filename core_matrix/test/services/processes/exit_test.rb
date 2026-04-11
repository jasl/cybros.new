require "test_helper"

class Processes::ExitTest < ActiveSupport::TestCase
  include ActionCable::TestHelper

  test "exits a running background service and appends a terminal status event" do
    process_context = build_process_context!
    process_run = Processes::Provision.call(
      workflow_node: process_context[:workflow_node],
      execution_runtime: process_context[:execution_runtime],
      kind: "background_service",
      command_line: "bin/dev",
      origin_message: process_context[:origin_message]
    ).process_run
    Processes::Activate.call(process_run: process_run)

    stopped = Processes::Exit.call(process_run: process_run, lifecycle_state: "stopped", reason: "manual_stop")

    assert stopped.stopped?
    assert_not_nil stopped.ended_at
    assert_equal "manual_stop", stopped.metadata["stop_reason"]
    assert_not stopped.execution_lease.active?

    last_event = WorkflowNodeEvent.where(workflow_node: process_context[:workflow_node]).order(:ordinal).last
    assert_equal "status", last_event.event_kind
    assert_equal "stopped", last_event.payload["state"]
  end

  test "broadcasts runtime.process_run.stopped on the conversation runtime stream" do
    process_context = build_process_context!
    process_run = Processes::Provision.call(
      workflow_node: process_context[:workflow_node],
      execution_runtime: process_context[:execution_runtime],
      kind: "background_service",
      command_line: "bin/dev",
      origin_message: process_context[:origin_message]
    ).process_run
    Processes::Activate.call(process_run: process_run)
    stream_name = ConversationRuntime::StreamName.for_conversation(process_context[:conversation])

    broadcasts = capture_broadcasts(stream_name) do
      Processes::Exit.call(process_run: process_run, lifecycle_state: "stopped", reason: "manual_stop")
    end

    assert_equal 1, broadcasts.size
    payload = broadcasts.first

    assert_equal "runtime.process_run.stopped", payload.fetch("event_kind")
    assert_equal process_context[:conversation].public_id, payload.fetch("conversation_id")
    assert_equal process_context[:turn].public_id, payload.fetch("turn_id")
    assert_equal process_run.public_id, payload.dig("payload", "process_run_id")
    assert_equal "background_service", payload.dig("payload", "kind")
    assert_equal "stopped", payload.dig("payload", "lifecycle_state")
    assert_equal "manual_stop", payload.dig("payload", "reason")
  end

  private

  def build_process_context!
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_snapshot: context[:agent_snapshot]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Process input",
      agent_snapshot: context[:agent_snapshot],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    workflow_run = create_workflow_run!(turn: turn)
    workflow_node = create_workflow_node!(workflow_run: workflow_run, metadata: {})

    {
      conversation: conversation,
      execution_runtime: context[:execution_runtime],
      origin_message: turn.selected_input_message,
      turn: turn,
      workflow_node: workflow_node,
    }.merge(context)
  end
end
