require "test_helper"

class TurnWorkflowBootstrapConstraintTest < NonTransactionalConcurrencyTestCase
  test "database constraint rejects pending bootstrap rows with a started timestamp" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      agent: context[:agent]
    )
    turn = Turns::AcceptPendingUserTurn.call(
      conversation: conversation,
      content: "Follow up",
      selector_source: "app_api",
      selector: "candidate:codex_subscription/gpt-5.3-codex"
    )

    error = assert_raises(ActiveRecord::StatementInvalid) do
      turn.update_column(:workflow_bootstrap_started_at, Time.current)
    end

    assert_includes error.message, "chk_turns_workflow_bootstrap_timestamps"
    assert_nil turn.reload.workflow_bootstrap_started_at
  end

  test "database constraint rejects pending bootstrap rows with malformed payload shape" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      agent: context[:agent]
    )
    turn = Turns::AcceptPendingUserTurn.call(
      conversation: conversation,
      content: "Follow up",
      selector_source: "app_api",
      selector: "candidate:codex_subscription/gpt-5.3-codex"
    )

    error = assert_raises(ActiveRecord::StatementInvalid) do
      turn.update_column(:workflow_bootstrap_payload, { "selector_source" => "app_api" })
    end

    assert_includes error.message, "chk_turns_workflow_bootstrap_payload_contract"
    assert_equal 6, turn.reload.workflow_bootstrap_payload.keys.size
  end

  test "database constraint rejects failed bootstrap rows with malformed failure payload" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      agent: context[:agent]
    )
    turn = Turns::AcceptPendingUserTurn.call(
      conversation: conversation,
      content: "Follow up",
      selector_source: "app_api",
      selector: "candidate:codex_subscription/gpt-5.3-codex"
    )

    error = assert_raises(ActiveRecord::StatementInvalid) do
      turn.update_columns(
        workflow_bootstrap_state: "failed",
        workflow_bootstrap_started_at: Time.current,
        workflow_bootstrap_finished_at: Time.current,
        workflow_bootstrap_failure_payload: {
          "error_class" => "RuntimeError",
          "error_message" => "boom",
        }
      )
    end

    assert_includes error.message, "chk_turns_workflow_bootstrap_failure_contract"
    assert_equal "pending", turn.reload.workflow_bootstrap_state
  end
end
