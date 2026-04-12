require "test_helper"

class Processes::ProvisionAndActivateTest < ActiveSupport::TestCase
  include ActionCable::TestHelper

  test "provisions a detached process in starting and then activates it with audit and runtime event" do
    process_context = build_process_context!

    provisioned = Processes::Provision.call(
      workflow_node: process_context[:workflow_node],
      execution_runtime: process_context[:execution_runtime],
      kind: "background_service",
      command_line: "echo hi",
      origin_message: process_context[:origin_message]
    ).process_run

    assert provisioned.starting?
    assert_equal process_context[:conversation], provisioned.conversation
    assert_equal process_context[:turn], provisioned.turn
    assert_equal process_context[:origin_message], provisioned.origin_message
    assert_equal process_context[:execution_runtime_connection].public_id, provisioned.execution_lease&.holder_key

    activated = Processes::Activate.call(process_run: provisioned)

    assert activated.running?

    status_events = WorkflowNodeEvent.where(workflow_node: process_context[:workflow_node], event_kind: "status").order(:ordinal)
    assert_equal %w[starting running], status_events.map { |event| event.payload.fetch("state") }

    audit_log = AuditLog.find_by!(action: "process_run.started")
    assert_equal activated, audit_log.subject
    assert_equal "background_service", audit_log.metadata["kind"]
    assert_equal process_context[:workflow_node].node_key, audit_log.metadata["workflow_node_key"]
  end

  test "activate broadcasts runtime.process_run.started on the conversation runtime stream" do
    process_context = build_process_context!
    provisioned = Processes::Provision.call(
      workflow_node: process_context[:workflow_node],
      execution_runtime: process_context[:execution_runtime],
      kind: "background_service",
      command_line: "echo hi",
      origin_message: process_context[:origin_message]
    ).process_run
    stream_name = ConversationRuntime::StreamName.for_conversation(process_context[:conversation])

    broadcasts = capture_broadcasts(stream_name) do
      Processes::Activate.call(process_run: provisioned)
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
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Process input",
      agent_definition_version: context[:agent_definition_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    workflow_run = create_workflow_run!(turn: turn)
    workflow_node = create_workflow_node!(workflow_run: workflow_run, metadata: { "policy_sensitive" => true })

    {
      conversation: conversation,
      execution_runtime: context[:execution_runtime],
      execution_runtime_connection: context[:execution_runtime_connection],
      origin_message: turn.selected_input_message,
      turn: turn,
      workflow_node: workflow_node,
    }.merge(context)
  end
end
