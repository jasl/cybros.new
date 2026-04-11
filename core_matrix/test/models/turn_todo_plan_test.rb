require "test_helper"

class TurnTodoPlanTest < ActiveSupport::TestCase
  test "validates owner alignment and one active plan per agent task run" do
    context = build_agent_control_context!
    scenario = MailboxScenarioBuilder.new(self).execution_assignment!(context: context)
    agent_task_run = scenario.fetch(:agent_task_run)

    association = TurnTodoPlan.reflect_on_association(:agent_task_run)

    assert_equal :belongs_to, association&.macro
    assert_equal %w[draft active blocked completed canceled failed], TurnTodoPlan::STATUSES

    TurnTodoPlan.create!(
      installation: agent_task_run.installation,
      agent_task_run: agent_task_run,
      conversation: agent_task_run.conversation,
      turn: agent_task_run.turn,
      status: "active",
      goal_summary: "Rebuild supervision around turn todo plans",
      current_item_key: "define-domain",
      counts_payload: {}
    )

    duplicate = TurnTodoPlan.new(
      installation: agent_task_run.installation,
      agent_task_run: agent_task_run,
      conversation: agent_task_run.conversation,
      turn: agent_task_run.turn,
      status: "active",
      goal_summary: "Second active plan",
      current_item_key: "duplicate",
      counts_payload: {}
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:agent_task_run], "already has an active turn todo plan"

    invalid_status = TurnTodoPlan.new(
      installation: agent_task_run.installation,
      agent_task_run: agent_task_run,
      conversation: agent_task_run.conversation,
      turn: agent_task_run.turn,
      status: "paused",
      goal_summary: "Invalid status",
      current_item_key: "invalid-status",
      counts_payload: {}
    )

    assert_not invalid_status.valid?
    assert_includes invalid_status.errors[:status], "is not included in the list"

    foreign_installation = Installation.new(
      name: "Foreign Installation #{next_test_sequence}",
      bootstrap_state: "bootstrapped",
      global_settings: {}
    )
    foreign_installation.save!(validate: false)

    mismatched_installation_plan = TurnTodoPlan.new(
      installation: foreign_installation,
      agent_task_run: agent_task_run,
      conversation: agent_task_run.conversation,
      turn: agent_task_run.turn,
      status: "draft",
      goal_summary: "Mismatched installation",
      current_item_key: "mismatched-installation",
      counts_payload: {}
    )

    assert_not mismatched_installation_plan.valid?
    assert_includes mismatched_installation_plan.errors[:agent_task_run], "must belong to the same installation"

    other_conversation = Conversations::CreateRoot.call(
      workspace: context.fetch(:workspace),
      agent: context.fetch(:agent)
    )
    other_turn = Turns::StartUserTurn.call(
      conversation: other_conversation,
      content: "Second turn",
      execution_runtime: context.fetch(:execution_runtime),
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    misaligned_plan = TurnTodoPlan.new(
      installation: agent_task_run.installation,
      agent_task_run: agent_task_run,
      conversation: other_conversation,
      turn: other_turn,
      status: "draft",
      goal_summary: "Misaligned owner",
      current_item_key: "misaligned-owner",
      counts_payload: {}
    )

    assert_not misaligned_plan.valid?
    assert_includes misaligned_plan.errors[:conversation], "must match the task conversation"
    assert_includes misaligned_plan.errors[:turn], "must match the task turn"
  end
end
