require "test_helper"

class Processes::StartTest < ActiveSupport::TestCase
  include ActionCable::TestHelper

  test "starts a policy-sensitive background service with audit and status event" do
    process_context = build_process_context!

    process_run = Processes::Start.call(
      workflow_node: process_context[:workflow_node],
      execution_environment: process_context[:execution_environment],
      kind: "background_service",
      command_line: "echo hi",
      origin_message: process_context[:origin_message]
    )

    assert process_run.running?
    assert_equal process_context[:conversation], process_run.conversation
    assert_equal process_context[:turn], process_run.turn
    assert_equal process_context[:origin_message], process_run.origin_message
    assert_equal process_context[:agent_deployment].public_id, process_run.execution_lease&.holder_key

    status_event = WorkflowNodeEvent.find_by!(workflow_node: process_context[:workflow_node], event_kind: "status")
    assert_equal "running", status_event.payload["state"]

    audit_log = AuditLog.find_by!(action: "process_run.started")
    assert_equal process_run, audit_log.subject
    assert_equal "background_service", audit_log.metadata["kind"]
    assert_equal process_context[:workflow_node].node_key, audit_log.metadata["workflow_node_key"]
  end

  test "broadcasts runtime.process_run.started on the conversation runtime stream" do
    process_context = build_process_context!
    stream_name = ConversationRuntime::StreamName.for_conversation(process_context[:conversation])

    broadcasts = capture_broadcasts(stream_name) do
      Processes::Start.call(
        workflow_node: process_context[:workflow_node],
        execution_environment: process_context[:execution_environment],
        kind: "background_service",
        command_line: "echo hi",
        origin_message: process_context[:origin_message]
      )
    end

    assert_equal 1, broadcasts.size
    payload = broadcasts.first

    assert_equal "runtime.process_run.started", payload.fetch("event_kind")
    assert_equal process_context[:conversation].public_id, payload.fetch("conversation_id")
    assert_equal process_context[:turn].public_id, payload.fetch("turn_id")
    assert_equal "background_service", payload.dig("payload", "kind")
    assert_equal "running", payload.dig("payload", "lifecycle_state")
    assert_equal "echo hi", payload.dig("payload", "command_line")
  end

  private

  def build_process_context!
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
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
    }.merge(context)
  end
end
