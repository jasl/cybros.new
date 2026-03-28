require "test_helper"

class TurnEntryFlowTest < ActionDispatch::IntegrationTest
  test "turn entry persists selector state, turn origins, and queued follow up state" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )

    Conversations::UpdateOverride.call(
      conversation: conversation,
      payload: {},
      schema_fingerprint: "schema-v1",
      selector_mode: "explicit_candidate",
      selector_provider_handle: "codex_subscription",
      selector_model_ref: "gpt-5.4"
    )

    active_turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Primary input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: { "temperature" => 0.3 },
      resolved_model_selection_snapshot: {
        "selector_source" => "conversation",
        "normalized_selector" => "candidate:codex_subscription/gpt-5.4",
      }
    )

    Turns::SteerCurrentInput.call(turn: active_turn, content: "Primary input revised")
    queued_turn = Turns::QueueFollowUp.call(
      conversation: conversation,
      content: "Queued follow up",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: { "temperature" => 0.3 },
      resolved_model_selection_snapshot: {
        "selector_source" => "conversation",
        "normalized_selector" => "candidate:codex_subscription/gpt-5.4",
      }
    )

    automation_conversation = Conversations::CreateAutomationRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    automation_turn = Turns::StartAutomationTurn.call(
      conversation: automation_conversation,
      origin_kind: "automation_webhook",
      origin_payload: { "event" => "push" },
      source_ref_type: "AutomationWebhook",
      source_ref_id: "hook-9",
      idempotency_key: "idemp-9",
      external_event_key: "evt-9",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {
        "selector_source" => "conversation",
        "normalized_selector" => "role:main",
      }
    )

    assert_equal "explicit_candidate", conversation.reload.interactive_selector_mode
    assert_equal "codex_subscription", conversation.interactive_selector_provider_handle
    assert_equal "gpt-5.4", conversation.interactive_selector_model_ref
    assert_equal "Primary input revised", active_turn.reload.selected_input_message.content
    assert queued_turn.queued?
    assert_nil automation_turn.selected_input_message
    assert_raises(ActiveRecord::RecordInvalid) do
      Turns::StartUserTurn.call(
        conversation: automation_conversation,
        content: "forbidden",
        agent_deployment: context[:agent_deployment],
        resolved_config_snapshot: {},
        resolved_model_selection_snapshot: {}
      )
    end
  end
end
