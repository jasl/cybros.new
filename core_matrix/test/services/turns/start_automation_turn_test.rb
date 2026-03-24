require "test_helper"

class Turns::StartAutomationTurnTest < ActiveSupport::TestCase
  test "starts an automation turn without a transcript bearing user message" do
    context = create_workspace_context!
    conversation = Conversations::CreateAutomationRoot.call(workspace: context[:workspace])

    turn = Turns::StartAutomationTurn.call(
      conversation: conversation,
      origin_kind: "automation_schedule",
      origin_payload: { "cron" => "0 9 * * *" },
      source_ref_type: "AutomationSchedule",
      source_ref_id: "schedule-1",
      idempotency_key: "idemp-1",
      external_event_key: "evt-1",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: { "temperature" => 0.1 },
      resolved_model_selection_snapshot: {
        "selector_source" => "conversation",
        "normalized_selector" => "role:main",
      }
    )

    assert turn.active?
    assert turn.automation_schedule?
    assert_equal({ "cron" => "0 9 * * *" }, turn.origin_payload)
    assert_nil turn.selected_input_message
    assert_nil turn.selected_output_message
  end
end
