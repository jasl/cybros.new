require "test_helper"

class Turns::SteerCurrentInputTest < ActiveSupport::TestCase
  test "creates a new selected input variant for the active turn" do
    context = create_workspace_context!
    turn = Turns::StartUserTurn.call(
      conversation: Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    ),
      content: "Original input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    steered = Turns::SteerCurrentInput.call(
      turn: turn,
      content: "Revised input"
    )

    assert_equal turn.id, steered.id
    assert_equal "Revised input", steered.selected_input_message.content
    assert_equal 1, steered.selected_input_message.variant_index
    assert_equal ["Original input", "Revised input"],
      UserMessage.where(turn: turn).order(:variant_index).pluck(:content)
  end

  test "queues follow up work after the first transcript side-effect boundary" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Original input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    create_workflow_run!(turn: turn)
    output = attach_selected_output!(turn, content: "Streaming output")

    queued = Turns::SteerCurrentInput.call(
      turn: turn,
      content: "Queued follow up",
      policy_mode: "queue"
    )

    assert queued.queued?
    assert_equal 2, queued.sequence
    assert_equal "Original input", turn.reload.selected_input_message.content
    assert_equal "Queued follow up", queued.selected_input_message.content
    assert_equal output.public_id, queued.origin_payload["expected_tail_message_id"]
    assert_equal turn.public_id, queued.origin_payload["queued_from_turn_id"]
  end

  test "detects side-effect boundaries from freshly persisted workflow node metadata" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Original input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    workflow_run = create_workflow_run!(turn: turn)

    turn.workflow_run.workflow_nodes.load
    create_workflow_node!(
      workflow_run: workflow_run,
      node_key: "first_side_effect",
      metadata: { "transcript_side_effect_committed" => true }
    )

    queued = Turns::SteerCurrentInput.call(
      turn: turn,
      content: "Queued from node metadata",
      policy_mode: "queue"
    )

    assert queued.queued?
    assert_equal "Queued from node metadata", queued.selected_input_message.content
  end

  test "rejects steering current input after the turn has been interrupted" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Original input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    Conversations::RequestTurnInterrupt.call(turn: turn, occurred_at: Time.current)

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Turns::SteerCurrentInput.call(turn: turn, content: "Should not steer")
    end

    assert_includes error.record.errors[:base], "must not steer current input after turn interruption"
  end
end
