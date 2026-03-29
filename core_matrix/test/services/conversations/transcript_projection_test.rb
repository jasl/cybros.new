require "test_helper"

class Conversations::TranscriptProjectionTest < ActiveSupport::TestCase
  test "forks inherit the full parent transcript" do
    context = create_workspace_context!
    root = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    first_turn = Turns::StartUserTurn.call(
      conversation: root,
      content: "Root input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    attach_selected_output!(first_turn, content: "Root output")
    fork = Conversations::CreateFork.call(parent: root)

    assert_equal ["Root input", "Root output"], Conversations::TranscriptProjection.call(conversation: fork).map(&:content)
  end

  test "hides local messages without removing inherited transcript entries" do
    context = create_workspace_context!
    root = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    root_turn = Turns::StartUserTurn.call(
      conversation: root,
      content: "Inherited root input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    branch = Conversations::CreateBranch.call(
      parent: root,
      historical_anchor_message_id: root_turn.selected_input_message_id
    )
    branch_turn = Turns::StartUserTurn.call(
      conversation: branch,
      content: "Hidden branch input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    Messages::UpdateVisibility.call(
      conversation: branch,
      message: branch_turn.selected_input_message,
      hidden: true
    )

    assert_equal ["Inherited root input"], Conversations::TranscriptProjection.call(conversation: branch).map(&:content)
  end
end
