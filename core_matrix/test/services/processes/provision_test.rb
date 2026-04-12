require "test_helper"

class Processes::ProvisionTest < ActiveSupport::TestCase
  test "persists the turn execution epoch on the process run" do
    process_context = build_process_context!

    provisioned = Processes::Provision.call(
      workflow_node: process_context[:workflow_node],
      execution_runtime: process_context[:execution_runtime],
      kind: "background_service",
      command_line: "echo hi",
      origin_message: process_context[:origin_message]
    ).process_run

    assert_equal process_context[:turn].execution_epoch, provisioned.execution_epoch
    assert_equal process_context[:execution_runtime], provisioned.execution_runtime
  end

  private

  def build_process_context!
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Process input",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    workflow_run = create_workflow_run!(turn: turn)
    workflow_node = create_workflow_node!(workflow_run: workflow_run, metadata: { "policy_sensitive" => true })

    {
      conversation: conversation,
      execution_runtime: context[:execution_runtime],
      origin_message: turn.selected_input_message,
      turn: turn,
      workflow_node: workflow_node,
    }.merge(context)
  end
end
