require "test_helper"

class ConversationControl::ResolveTargetRuntimeTest < ActiveSupport::TestCase
  test "chooses the newest active turn while keeping the current active workflow" do
    context = build_agent_control_context!
    newer_turn = Turns::StartUserTurn.call(
      conversation: context[:conversation],
      content: "Newer control turn",
      execution_runtime: context[:execution_runtime],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    result = ConversationControl::ResolveTargetRuntime.call(
      conversation: context[:conversation],
      request_kind: "send_guidance_to_active_agent",
      request_payload: {}
    )

    assert_equal newer_turn, result.active_turn
    assert_equal context[:workflow_run], result.workflow_run
  end

  test "prefers persisted latest-active anchors over query ordering once the fields exist" do
    context = build_agent_control_context!
    newer_turn = Turns::StartUserTurn.call(
      conversation: context[:conversation],
      content: "Newer control turn",
      execution_runtime: context[:execution_runtime],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    assert_equal newer_turn, context[:conversation].turns.where(lifecycle_state: "active").order(:created_at, :id).last
    context[:conversation].update!(
      latest_active_turn_id: context[:turn].id,
      latest_active_workflow_run_id: context[:workflow_run].id
    )

    result = ConversationControl::ResolveTargetRuntime.call(
      conversation: context[:conversation],
      request_kind: "send_guidance_to_active_agent",
      request_payload: {}
    )

    assert_equal context[:turn], result.active_turn
    assert_equal context[:workflow_run], result.workflow_run
  end
end
