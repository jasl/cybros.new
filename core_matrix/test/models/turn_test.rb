require "test_helper"

class TurnTest < ActiveSupport::TestCase
  test "enforces unique sequence numbers within a conversation" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])

    Turn.create!(
      installation: context[:installation],
      conversation: conversation,
      agent_deployment: context[:agent_deployment],
      sequence: 1,
      lifecycle_state: "active",
      origin_kind: "manual_user",
      origin_payload: {},
      pinned_deployment_fingerprint: context[:agent_deployment].fingerprint,
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    duplicate = Turn.new(
      installation: context[:installation],
      conversation: conversation,
      agent_deployment: context[:agent_deployment],
      sequence: 1,
      lifecycle_state: "queued",
      origin_kind: "automation_schedule",
      origin_payload: {},
      pinned_deployment_fingerprint: context[:agent_deployment].fingerprint,
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:sequence], "has already been taken"
  end

  test "persists structured origin metadata and state helpers" do
    context = create_workspace_context!
    conversation = Conversations::CreateAutomationRoot.call(workspace: context[:workspace])

    queued = Turn.new(
      installation: context[:installation],
      conversation: conversation,
      agent_deployment: context[:agent_deployment],
      sequence: 1,
      lifecycle_state: "queued",
      origin_kind: "automation_schedule",
      origin_payload: { "cron" => "0 9 * * *" },
      source_ref_type: "AutomationSchedule",
      source_ref_id: "schedule-1",
      idempotency_key: "idemp-1",
      external_event_key: "evt-1",
      pinned_deployment_fingerprint: context[:agent_deployment].fingerprint,
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    terminal = Turn.new(
      installation: context[:installation],
      conversation: conversation,
      agent_deployment: context[:agent_deployment],
      sequence: 2,
      lifecycle_state: "completed",
      origin_kind: "automation_webhook",
      origin_payload: { "webhook" => "github" },
      source_ref_type: "AutomationWebhook",
      source_ref_id: "hook-1",
      idempotency_key: "idemp-2",
      external_event_key: "evt-2",
      pinned_deployment_fingerprint: context[:agent_deployment].fingerprint,
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    assert queued.valid?
    assert terminal.valid?
    assert queued.queued?
    assert terminal.completed?
    assert terminal.terminal?
  end
end
