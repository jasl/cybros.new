require "test_helper"

class TurnTest < ActiveSupport::TestCase
  test "generates and resolves a public id" do
    context = create_workspace_context!
    turn = Turns::StartUserTurn.call(
      conversation: Conversations::CreateRoot.call(workspace: context[:workspace]),
      content: "Hello",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    assert turn.public_id.present?
    assert_equal turn, Turn.find_by_public_id!(turn.public_id)
  end

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

  test "exposes resolved model selection snapshot helpers" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    turn = Turn.new(
      installation: context[:installation],
      conversation: conversation,
      agent_deployment: context[:agent_deployment],
      sequence: 1,
      lifecycle_state: "active",
      origin_kind: "manual_user",
      origin_payload: {},
      pinned_deployment_fingerprint: context[:agent_deployment].fingerprint,
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {
        "normalized_selector" => "role:main",
        "resolved_provider_handle" => "codex_subscription",
        "resolved_model_ref" => "gpt-5.4",
      }
    )

    assert_equal "role:main", turn.normalized_selector
    assert_equal "codex_subscription", turn.resolved_provider_handle
    assert_equal "gpt-5.4", turn.resolved_model_ref
  end

  test "exposes execution context helpers from a wrapped resolved config snapshot" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    turn = Turn.new(
      installation: context[:installation],
      conversation: conversation,
      agent_deployment: context[:agent_deployment],
      sequence: 1,
      lifecycle_state: "active",
      origin_kind: "manual_user",
      origin_payload: {},
      pinned_deployment_fingerprint: context[:agent_deployment].fingerprint,
      resolved_config_snapshot: {
        "config" => { "temperature" => 0.2 },
        "execution_context" => {
          "identity" => {
            "user_id" => context[:user].id.to_s,
            "workspace_id" => context[:workspace].id.to_s,
          },
          "attachment_manifest" => [{ "attachment_id" => "att-1" }],
          "model_input_attachments" => [{ "attachment_id" => "att-1" }],
        },
      },
      resolved_model_selection_snapshot: {}
    )

    assert_equal({ "temperature" => 0.2 }, turn.effective_config_snapshot)
    assert_equal context[:user].id.to_s, turn.execution_identity["user_id"]
    assert_equal context[:workspace].id.to_s, turn.execution_identity["workspace_id"]
    assert_equal ["att-1"], turn.attachment_manifest.map { |item| item.fetch("attachment_id") }
    assert_equal ["att-1"], turn.model_input_attachments.map { |item| item.fetch("attachment_id") }
  end
end
