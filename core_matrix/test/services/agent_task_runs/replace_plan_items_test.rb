require "test_helper"

class AgentTaskRuns::ReplacePlanItemsTest < ActiveSupport::TestCase
  test "replaces plan items and refreshes task rollups" do
    context = build_agent_control_context!
    agent_task_run = create_agent_task_run!(
      workflow_node: context[:workflow_node],
      lifecycle_state: "running",
      started_at: Time.current,
      supervision_state: "running",
      focus_kind: "planning",
      last_progress_at: 5.minutes.ago,
      supervision_payload: {}
    )
    owner_conversation = context[:conversation]
    child_conversation = create_conversation_record!(
      workspace: context[:workspace],
      parent_conversation: owner_conversation,
      execution_runtime: context[:execution_runtime],
      agent_program_version: context[:agent_program_version],
      kind: "fork",
      addressability: "agent_addressable"
    )
    delegated_subagent_session = SubagentSession.create!(
      installation: context[:installation],
      owner_conversation: owner_conversation,
      conversation: child_conversation,
      scope: "conversation",
      profile_key: "worker",
      depth: 0
    )

    AgentTaskPlanItem.create!(
      installation: context[:installation],
      agent_task_run: agent_task_run,
      item_key: "old",
      title: "Old item",
      status: "pending",
      position: 0,
      details_payload: {}
    )

    AgentTaskRuns::ReplacePlanItems.call(
      agent_task_run: agent_task_run,
      plan_items: [
        {
          "item_key" => "plan",
          "title" => "Rebuild supervision plan",
          "status" => "pending",
          "position" => 0
        },
        {
          "item_key" => "projection",
          "title" => "Project the new runtime state",
          "status" => "in_progress",
          "position" => 1,
          "parent_item_key" => "plan",
          "delegated_subagent_session_public_id" => delegated_subagent_session.public_id
        },
        {
          "item_key" => "renderer",
          "title" => "Update the renderer",
          "status" => "pending",
          "position" => 2
        }
      ]
    )

    agent_task_run.reload
    plan_items = agent_task_run.agent_task_plan_items.order(:position).to_a

    assert_equal %w[plan projection renderer], plan_items.map(&:item_key)
    assert_equal "Project the new runtime state", agent_task_run.current_focus_summary
    assert_equal "Update the renderer", agent_task_run.next_step_hint
    assert agent_task_run.last_progress_at.present?
    assert_equal delegated_subagent_session, plan_items.second.delegated_subagent_session
    assert_equal plan_items.first, plan_items.second.parent_plan_item
  end

  test "resolves parent links regardless of incoming payload order" do
    context = build_agent_control_context!
    agent_task_run = create_agent_task_run!(
      workflow_node: context[:workflow_node],
      lifecycle_state: "running",
      started_at: Time.current,
      supervision_state: "running",
      focus_kind: "planning",
      last_progress_at: 5.minutes.ago,
      supervision_payload: {}
    )

    AgentTaskRuns::ReplacePlanItems.call(
      agent_task_run: agent_task_run,
      plan_items: [
        {
          "item_key" => "projection",
          "title" => "Project the new runtime state",
          "status" => "in_progress",
          "position" => 1,
          "parent_item_key" => "plan"
        },
        {
          "item_key" => "plan",
          "title" => "Rebuild supervision plan",
          "status" => "pending",
          "position" => 0
        }
      ]
    )

    plan_item = agent_task_run.reload.agent_task_plan_items.find_by!(item_key: "projection")
    assert_equal "plan", plan_item.parent_plan_item&.item_key
  end

  test "rejects delegated sessions that are not owned by the task conversation" do
    context = build_agent_control_context!
    agent_task_run = create_agent_task_run!(
      workflow_node: context[:workflow_node],
      lifecycle_state: "running",
      started_at: Time.current,
      supervision_state: "running",
      focus_kind: "planning",
      last_progress_at: 5.minutes.ago,
      supervision_payload: {}
    )
    unrelated_owner = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_program_version: context[:agent_program_version]
    )
    unrelated_child = create_conversation_record!(
      workspace: context[:workspace],
      installation: context[:installation],
      parent_conversation: unrelated_owner,
      execution_runtime: context[:execution_runtime],
      agent_program_version: context[:agent_program_version],
      kind: "fork",
      addressability: "agent_addressable"
    )
    unrelated_session = SubagentSession.create!(
      installation: context[:installation],
      owner_conversation: unrelated_owner,
      conversation: unrelated_child,
      scope: "conversation",
      profile_key: "worker",
      depth: 0
    )

    assert_raises(ActiveRecord::RecordNotFound) do
      AgentTaskRuns::ReplacePlanItems.call(
        agent_task_run: agent_task_run,
        plan_items: [
          {
            "item_key" => "projection",
            "title" => "Project the new runtime state",
            "status" => "in_progress",
            "position" => 0,
            "delegated_subagent_session_public_id" => unrelated_session.public_id
          }
        ]
      )
    end
  end

  test "accepts key aliases from the supervision update contract" do
    context = build_agent_control_context!
    agent_task_run = create_agent_task_run!(
      workflow_node: context[:workflow_node],
      lifecycle_state: "running",
      started_at: Time.current,
      supervision_state: "running",
      focus_kind: "planning",
      last_progress_at: 5.minutes.ago,
      supervision_payload: {}
    )

    AgentTaskRuns::ReplacePlanItems.call(
      agent_task_run: agent_task_run,
      plan_items: [
        {
          "key" => "projection",
          "title" => "Add conversation supervision state",
          "status" => "in_progress",
          "position" => 0
        }
      ]
    )

    assert_equal ["projection"], agent_task_run.reload.agent_task_plan_items.order(:position).pluck(:item_key)
  end
end
