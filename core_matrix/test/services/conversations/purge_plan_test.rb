require "test_helper"

class Conversations::PurgePlanTest < ActiveSupport::TestCase
  test "removes owned rows so remaining_owned_rows? flips false after execute" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_program_version: context[:agent_program_version]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Purge plan input",
      agent_program_version: context[:agent_program_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    workflow_run = create_workflow_run!(turn: turn)
    create_workflow_node!(workflow_run: workflow_run)
    attach_selected_output!(turn, content: "Purge plan output")
    plan = Conversations::PurgePlan.new(conversation: conversation)

    assert plan.remaining_owned_rows?

    plan.execute!

    assert_not plan.remaining_owned_rows?
    assert_not Message.exists?(turn.selected_input_message_id)
    assert_not WorkflowRun.exists?(workflow_run.id)
    assert_not Turn.exists?(turn.id)
  end
end
