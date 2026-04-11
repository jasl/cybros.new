require "test_helper"

class Turns::FeaturePolicyEnforcementTest < ActiveSupport::TestCase
  test "freezes the conversation feature policy on turns workflow runs and agent task runs" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_snapshot: context[:agent_snapshot]
    )
    conversation.update!(
      enabled_feature_ids: %w[tool_invocation message_attachments conversation_archival],
      during_generation_input_policy: "restart"
    )

    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Feature policy input",
      agent_snapshot: context[:agent_snapshot],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    workflow_run = create_workflow_run!(turn: turn)
    workflow_node = create_workflow_node!(workflow_run: workflow_run)
    task_run = create_agent_task_run!(workflow_node: workflow_node)

    expected_snapshot = {
      "enabled_feature_ids" => %w[tool_invocation message_attachments conversation_archival],
      "during_generation_input_policy" => "restart",
    }

    assert_equal expected_snapshot, turn.feature_policy_snapshot
    assert_equal expected_snapshot, workflow_run.feature_policy_snapshot
    assert_equal expected_snapshot, task_run.feature_policy_snapshot

    conversation.update!(
      enabled_feature_ids: Conversation::FEATURE_IDS,
      during_generation_input_policy: "queue"
    )

    assert_equal expected_snapshot, turn.reload.feature_policy_snapshot
    assert_equal expected_snapshot, workflow_run.reload.feature_policy_snapshot
    assert_equal expected_snapshot, task_run.reload.feature_policy_snapshot
  end

  test "automation turns freeze human interaction disabled by default" do
    context = create_workspace_context!
    conversation = Conversations::CreateAutomationRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_snapshot: context[:agent_snapshot]
    )

    turn = Turns::StartAutomationTurn.call(
      conversation: conversation,
      origin_kind: "automation_schedule",
      origin_payload: { "cron" => "0 9 * * *" },
      source_ref_type: "AutomationSchedule",
      source_ref_id: "schedule-automation",
      idempotency_key: "automation-feature-policy",
      external_event_key: "automation-feature-policy",
      agent_snapshot: context[:agent_snapshot],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    refute turn.feature_policy_snapshot.fetch("enabled_feature_ids").include?("human_interaction")
  end

  test "steering current input uses the frozen turn policy instead of the current conversation policy" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_snapshot: context[:agent_snapshot]
    )
    conversation.update!(during_generation_input_policy: "reject")

    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Original input",
      agent_snapshot: context[:agent_snapshot],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    create_workflow_run!(turn: turn)
    attach_selected_output!(turn, content: "Existing output")

    conversation.update!(during_generation_input_policy: "queue")

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Turns::SteerCurrentInput.call(
        turn: turn,
        content: "New input after policy drift"
      )
    end

    assert_includes error.record.errors[:base], "reject policy does not allow new input while active work exists"
    assert_equal 0, conversation.turns.where(lifecycle_state: "queued").count
  end

  test "branching rejects disabled conversation feature ids with a structured policy error" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_snapshot: context[:agent_snapshot]
    )
    anchor_turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Branch anchor",
      agent_snapshot: context[:agent_snapshot],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    conversation.update!(
      enabled_feature_ids: Conversation::FEATURE_IDS - ["conversation_branching"]
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::CreateBranch.call(
        parent: conversation,
        historical_anchor_message_id: anchor_turn.selected_input_message_id
      )
    end

    detail = error.record.errors.details.fetch(:base).find { |candidate| candidate[:error] == :feature_not_enabled }
    assert_equal "conversation_branching", detail.fetch(:feature_id)
  end

  test "archive rejects disabled conversation feature ids with a structured policy error" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_snapshot: context[:agent_snapshot]
    )
    conversation.update!(
      enabled_feature_ids: Conversation::FEATURE_IDS - ["conversation_archival"]
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::Archive.call(conversation: conversation)
    end

    detail = error.record.errors.details.fetch(:base).find { |candidate| candidate[:error] == :feature_not_enabled }
    assert_equal "conversation_archival", detail.fetch(:feature_id)
  end
end
