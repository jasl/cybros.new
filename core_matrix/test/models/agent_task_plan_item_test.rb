require "test_helper"

class AgentTaskPlanItemTest < ActiveSupport::TestCase
  test "supports one in-progress item per task with nested and delegated links" do
    context = build_agent_control_context!
    agent_task_run = create_agent_task_run!(workflow_node: context[:workflow_node])
    owner_conversation = context[:conversation]
    child_conversation = create_conversation_record!(
      workspace: context[:workspace],
      parent_conversation: owner_conversation,
      execution_runtime: context[:execution_runtime],
      agent_program_version: context[:agent_program_version],
      kind: "fork",
      addressability: "agent_addressable"
    )
    subagent_session = SubagentSession.create!(
      installation: context[:installation],
      owner_conversation: owner_conversation,
      conversation: child_conversation,
      scope: "conversation",
      profile_key: "worker",
      depth: 0
    )

    parent_item = AgentTaskPlanItem.create!(
      installation: context[:installation],
      agent_task_run: agent_task_run,
      item_key: "plan",
      title: "Rebuild the supervision projection",
      status: "pending",
      position: 0,
      details_payload: {}
    )

    child_item = AgentTaskPlanItem.create!(
      installation: context[:installation],
      agent_task_run: agent_task_run,
      parent_plan_item: parent_item,
      delegated_subagent_session: subagent_session,
      item_key: "projection",
      title: "Wire the projector into report handling",
      status: "in_progress",
      position: 1,
      details_payload: {}
    )

    assert child_item.public_id.present?
    assert_equal parent_item, child_item.parent_plan_item
    assert_equal subagent_session, child_item.delegated_subagent_session

    duplicate_in_progress = AgentTaskPlanItem.new(
      installation: context[:installation],
      agent_task_run: agent_task_run,
      item_key: "renderer",
      title: "Rebuild the renderer",
      status: "in_progress",
      position: 2,
      details_payload: {}
    )

    assert_not duplicate_in_progress.valid?
    assert_includes duplicate_in_progress.errors[:status], "only one plan item may be in progress per task"
  end
end
