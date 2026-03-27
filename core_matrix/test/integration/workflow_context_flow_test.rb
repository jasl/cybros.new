require "test_helper"

class WorkflowContextFlowTest < ActionDispatch::IntegrationTest
  test "branch workflow context uses local imports and does not pull branch-ineligible attachments" do
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    root = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    anchor_turn = Turns::StartUserTurn.call(
      conversation: root,
      content: "Anchor input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    anchor_attachment = create_message_attachment!(
      message: anchor_turn.selected_input_message,
      filename: "anchor.txt",
      content_type: "text/plain",
      body: "anchor"
    )
    later_root_turn = Turns::StartUserTurn.call(
      conversation: root,
      content: "Later root input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    later_root_attachment = create_message_attachment!(
      message: later_root_turn.selected_input_message,
      filename: "later.txt",
      content_type: "text/plain",
      body: "later"
    )
    summary_segment = ConversationSummaries::CreateSegment.call(
      conversation: root,
      start_message: anchor_turn.selected_input_message,
      end_message: anchor_turn.selected_input_message,
      content: "Anchor summary"
    )
    branch = Conversations::CreateBranch.call(
      parent: root,
      historical_anchor_message_id: anchor_turn.selected_input_message.id
    )
    Conversations::AddImport.call(
      conversation: branch,
      kind: "quoted_context",
      summary_segment: summary_segment
    )
    branch_turn = Turns::StartUserTurn.call(
      conversation: branch,
      content: "Branch input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: { "temperature" => 0.3 },
      resolved_model_selection_snapshot: {}
    )
    branch_attachment = create_message_attachment!(
      message: branch_turn.selected_input_message,
      filename: "branch.png",
      content_type: "image/png",
      body: "png"
    )

    workflow_run = Workflows::CreateForTurn.call(
      turn: branch_turn,
      root_node_key: "root",
      root_node_type: "turn_root",
      decision_source: "system",
      metadata: {}
    )
    projection = Conversations::ContextProjection.call(conversation: branch)

    refute_respond_to branch, :context_projection_messages
    assert_equal(
      [
        anchor_turn.selected_input_message.public_id,
        branch_turn.selected_input_message.public_id,
      ],
      projection.messages.map(&:public_id)
    )
    assert_equal %w[branch_prefix quoted_context], branch_turn.execution_snapshot.context_imports.map { |item| item.fetch("kind") }.sort
    expected_attachment_ids = [anchor_attachment.public_id, branch_attachment.public_id].sort

    assert_equal expected_attachment_ids, projection.attachments.map(&:public_id).sort
    refute_includes projection.attachments.map(&:public_id), later_root_attachment.public_id
    assert_equal expected_attachment_ids, workflow_run.model_input_attachments.map { |item| item.fetch("attachment_id") }.sort
    assert_equal "Anchor summary", branch_turn.execution_snapshot.context_imports.find { |item| item.fetch("kind") == "quoted_context" }.fetch("content")
  end
end
