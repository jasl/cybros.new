require "test_helper"

class TurnTest < ActiveSupport::TestCase
  test "generates and resolves a public id" do
    context = create_workspace_context!
    turn = Turns::StartUserTurn.call(
      conversation: Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    ),
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
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )

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
    conversation = Conversations::CreateAutomationRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )

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

  test "requires cancellation reason and timestamp to be paired" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
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
      resolved_model_selection_snapshot: {},
      cancellation_reason_kind: "conversation_deleted"
    )

    assert turn.invalid?
    assert_includes turn.errors[:cancellation_requested_at], "must exist when cancellation reason is present"
  end

  test "exposes resolved model selection snapshot helpers" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
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

  test "rejects non-hash execution snapshot payloads" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
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
      execution_snapshot_payload: "invalid",
      resolved_model_selection_snapshot: {}
    )

    assert turn.invalid?
    assert_includes turn.errors[:execution_snapshot_payload], "must be a hash"
  end

  test "returns an explicit execution snapshot reader" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    turn = Turn.new(
      installation: context[:installation],
      conversation: conversation,
      agent_deployment: context[:agent_deployment],
      sequence: 1,
      lifecycle_state: "active",
      origin_kind: "manual_user",
      origin_payload: {},
      pinned_deployment_fingerprint: context[:agent_deployment].fingerprint,
      resolved_config_snapshot: { "temperature" => 0.2 },
      execution_snapshot_payload: {
        "identity" => {
          "user_id" => context[:user].public_id,
          "workspace_id" => context[:workspace].public_id,
        },
        "attachment_manifest" => [{ "attachment_id" => "att-1" }],
      },
      resolved_model_selection_snapshot: {}
    )

    assert_equal context[:user].public_id, turn.execution_snapshot.identity["user_id"]
    assert_equal context[:workspace].public_id, turn.execution_snapshot.identity["workspace_id"]
    assert_equal ["att-1"], turn.execution_snapshot.attachment_manifest.map { |item| item.fetch("attachment_id") }
  end

  test "rejects a deployment outside the conversation execution environment" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    other_environment = create_execution_environment!(installation: context[:installation])
    other_deployment = create_agent_deployment!(
      installation: context[:installation],
      agent_installation: create_agent_installation!(installation: context[:installation]),
      execution_environment: other_environment,
      fingerprint: "other-env-#{next_test_sequence}",
      bootstrap_state: "pending"
    )
    turn = Turn.new(
      installation: context[:installation],
      conversation: conversation,
      agent_deployment: other_deployment,
      sequence: 1,
      lifecycle_state: "active",
      origin_kind: "manual_user",
      origin_payload: {},
      pinned_deployment_fingerprint: other_deployment.fingerprint,
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    assert turn.invalid?
    assert_includes turn.errors[:agent_deployment], "must belong to the bound execution environment"
  end

  test "rejects selected output lineage that does not match the selected input" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "First input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    first_input = turn.selected_input_message
    first_output = attach_selected_output!(turn, content: "First output")
    edited_turn = Turns::EditTailInput.call(turn: turn, content: "Second input")

    edited_turn.selected_output_message = first_output

    assert edited_turn.invalid?
    assert_includes edited_turn.errors[:selected_output_message], "must belong to the selected input lineage"
    assert_equal first_input, first_output.source_input_message
  end
end
