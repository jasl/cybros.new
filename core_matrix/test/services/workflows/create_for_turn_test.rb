require "test_helper"

class Workflows::CreateForTurnTest < ActiveSupport::TestCase
  test "creates one active workflow with a root node for the turn" do
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: { "temperature" => 0.2 },
      resolved_model_selection_snapshot: {}
    )
    attachment = create_message_attachment!(
      message: turn.selected_input_message,
      filename: "brief.pdf",
      content_type: "application/pdf",
      body: "brief"
    )

    workflow_run = Workflows::CreateForTurn.call(
      turn: turn,
      root_node_key: "root",
      root_node_type: "turn_root",
      decision_source: "system",
      metadata: { "policy_sensitive" => true }
    )

    assert workflow_run.active?
    assert_equal turn, workflow_run.turn
    assert_equal 1, workflow_run.workflow_nodes.count
    assert_equal "root", workflow_run.workflow_nodes.first.node_key
    assert_equal 0, workflow_run.workflow_nodes.first.ordinal
    assert_equal "role:main", turn.reload.resolved_model_selection_snapshot["normalized_selector"]
    assert_equal "codex_subscription", workflow_run.resolved_provider_handle
    assert_equal "gpt-5.4", workflow_run.resolved_model_ref
    assert_equal({ "temperature" => 0.2 }, turn.resolved_config_snapshot)
    refute turn.resolved_config_snapshot.key?(legacy_snapshot_context_key)
    assert_equal turn.public_id, turn.execution_snapshot.identity["turn_id"]
    assert_equal context[:user].public_id, turn.execution_snapshot.identity["user_id"]
    assert_equal context[:workspace].public_id, turn.execution_snapshot.identity["workspace_id"]
    assert_equal context[:execution_environment].public_id, turn.execution_snapshot.identity["execution_environment_id"]
    assert_equal [attachment.public_id], turn.execution_snapshot.runtime_attachment_manifest.map { |item| item.fetch("attachment_id") }
    assert_equal [attachment.public_id], turn.execution_snapshot.model_input_attachments.map { |item| item.fetch("attachment_id") }
    assert_equal turn.execution_snapshot.to_h, turn.execution_snapshot_payload
    assert_raises(NameError) { Workflows::ContextAssembler }
  end

  test "rejects a second active workflow in the same conversation" do
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    first_turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "First input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    second_turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Second input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    Workflows::CreateForTurn.call(
      turn: first_turn,
      root_node_key: "root",
      root_node_type: "turn_root",
      decision_source: "system",
      metadata: {}
    )

    assert_raises(ActiveRecord::RecordInvalid) do
      Workflows::CreateForTurn.call(
        turn: second_turn,
        root_node_key: "root-2",
        root_node_type: "turn_root",
        decision_source: "system",
        metadata: {}
      )
    end
  end
end
