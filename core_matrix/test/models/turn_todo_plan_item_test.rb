require "test_helper"

class TurnTodoPlanItemTest < ActiveSupport::TestCase
  test "validates item key uniqueness and delegated subagent alignment" do
    fixture = build_turn_todo_plan_fixture!

    association = TurnTodoPlanItem.reflect_on_association(:turn_todo_plan)

    assert_equal :belongs_to, association&.macro
    assert_equal %w[pending in_progress completed blocked canceled failed], TurnTodoPlanItem::STATUSES

    fixture.fetch(:plan).turn_todo_plan_items.create!(
      installation: fixture.fetch(:installation),
      item_key: "define-domain",
      title: "Define the plan domain",
      status: "completed",
      position: 0,
      kind: "implementation",
      details_payload: {},
      depends_on_item_keys: []
    )

    duplicate = fixture.fetch(:plan).turn_todo_plan_items.new(
      installation: fixture.fetch(:installation),
      item_key: "define-domain",
      title: "Duplicate",
      status: "pending",
      position: 1,
      kind: "implementation",
      details_payload: {},
      depends_on_item_keys: []
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:item_key], "has already been taken"

    invalid_status = fixture.fetch(:plan).turn_todo_plan_items.new(
      installation: fixture.fetch(:installation),
      item_key: "invalid-status",
      title: "Invalid status",
      status: "draft",
      position: 1,
      kind: "implementation",
      details_payload: {},
      depends_on_item_keys: []
    )

    assert_not invalid_status.valid?
    assert_includes invalid_status.errors[:status], "is not included in the list"

    invalid_dependencies = fixture.fetch(:plan).turn_todo_plan_items.new(
      installation: fixture.fetch(:installation),
      item_key: "invalid-dependencies",
      title: "Invalid dependencies",
      status: "pending",
      position: 1,
      kind: "implementation",
      details_payload: {},
      depends_on_item_keys: "define-domain"
    )

    assert_not invalid_dependencies.valid?
    assert_includes invalid_dependencies.errors[:depends_on_item_keys], "must be an array"

    unrelated_owner = Conversations::CreateRoot.call(
      workspace: fixture.fetch(:context).fetch(:workspace),
      agent: fixture.fetch(:context).fetch(:agent)
    )
    unrelated_child = create_conversation_record!(
      workspace: fixture.fetch(:context).fetch(:workspace),
      installation: fixture.fetch(:installation),
      parent_conversation: unrelated_owner,
      execution_runtime: fixture.fetch(:context).fetch(:execution_runtime),
      agent_definition_version: fixture.fetch(:context).fetch(:agent_definition_version),
      kind: "fork",
      addressability: "agent_addressable"
    )
    unrelated_session = SubagentConnection.create!(
      installation: fixture.fetch(:installation),
      owner_conversation: unrelated_owner,
      conversation: unrelated_child,
      scope: "conversation",
      profile_key: "worker",
      depth: 0
    )

    misaligned_session_item = fixture.fetch(:plan).turn_todo_plan_items.new(
      installation: fixture.fetch(:installation),
      delegated_subagent_connection: unrelated_session,
      item_key: "delegate-misaligned",
      title: "Misaligned delegated session",
      status: "pending",
      position: 1,
      kind: "implementation",
      details_payload: {},
      depends_on_item_keys: []
    )

    assert_not misaligned_session_item.valid?
    assert_includes misaligned_session_item.errors[:delegated_subagent_connection], "must be owned by the plan conversation"
  end

  private

  def build_turn_todo_plan_fixture!
    context = build_agent_control_context!
    agent_task_run = create_agent_task_run!(workflow_node: context.fetch(:workflow_node))
    child_conversation = create_conversation_record!(
      workspace: context.fetch(:workspace),
      installation: context.fetch(:installation),
      parent_conversation: context.fetch(:conversation),
      execution_runtime: context.fetch(:execution_runtime),
      agent_definition_version: context.fetch(:agent_definition_version),
      kind: "fork",
      addressability: "agent_addressable"
    )
    subagent_connection = SubagentConnection.create!(
      installation: context.fetch(:installation),
      owner_conversation: context.fetch(:conversation),
      conversation: child_conversation,
      scope: "conversation",
      profile_key: "worker",
      depth: 0
    )
    plan = TurnTodoPlan.create!(
      installation: context.fetch(:installation),
      agent_task_run: agent_task_run,
      conversation: agent_task_run.conversation,
      turn: agent_task_run.turn,
      status: "active",
      goal_summary: "Rebuild supervision around turn todo plans",
      current_item_key: "define-domain",
      counts_payload: {}
    )

    {
      context: context,
      installation: context.fetch(:installation),
      agent_task_run: agent_task_run,
      plan: plan,
      subagent_connection: subagent_connection,
    }
  end
end
