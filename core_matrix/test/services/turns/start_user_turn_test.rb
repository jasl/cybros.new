require "test_helper"

class Turns::StartUserTurnTest < ActiveSupport::TestCase
  test "starts an active manual user turn with a selected input message" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])

    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Hello world",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: { "temperature" => 0.2 },
      resolved_model_selection_snapshot: {
        "selector_source" => "conversation",
        "normalized_selector" => "role:main",
      }
    )

    assert turn.active?
    assert turn.manual_user?
    assert_equal 1, turn.sequence
    assert_equal context[:agent_deployment].fingerprint, turn.pinned_deployment_fingerprint
    assert_equal({ "temperature" => 0.2 }, turn.resolved_config_snapshot)
    assert_equal "role:main", turn.resolved_model_selection_snapshot.fetch("normalized_selector")
    assert_instance_of UserMessage, turn.selected_input_message
    assert_equal "Hello world", turn.selected_input_message.content
    assert_nil turn.selected_output_message
  end

  test "rejects automation purpose conversations" do
    context = create_workspace_context!
    conversation = Conversations::CreateAutomationRoot.call(workspace: context[:workspace])

    assert_raises(ActiveRecord::RecordInvalid) do
      Turns::StartUserTurn.call(
        conversation: conversation,
        content: "This should fail",
        agent_deployment: context[:agent_deployment],
        resolved_config_snapshot: {},
        resolved_model_selection_snapshot: {}
      )
    end
  end
end
