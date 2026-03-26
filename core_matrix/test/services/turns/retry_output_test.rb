require "test_helper"

class Turns::RetryOutputTest < ActiveSupport::TestCase
  test "retries a failed output by creating a new output variant in the same turn" do
    context = create_workspace_context!
    turn = Turns::StartUserTurn.call(
      conversation: Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    ),
      content: "Input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    output = attach_selected_output!(turn, content: "Failed output")
    turn.update!(lifecycle_state: "failed")

    retried = Turns::RetryOutput.call(
      message: output,
      content: "Retried output"
    )

    assert_equal turn.id, retried.id
    assert retried.active?
    assert_equal "Retried output", retried.selected_output_message.content
    assert_equal 1, retried.selected_output_message.variant_index
  end
end
