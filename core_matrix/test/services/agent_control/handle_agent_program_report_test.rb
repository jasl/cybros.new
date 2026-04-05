require "test_helper"

class AgentControl::HandleAgentProgramReportTest < ActiveSupport::TestCase
  test "accepts terminal agent program reports for a leased mailbox item" do
    context = build_agent_control_context!
    scenario = MailboxScenarioBuilder.new(self).agent_program_request!(
      context: context,
      request_kind: "prepare_round",
      payload: {
        "workflow_node_id" => context.fetch(:workflow_node).public_id,
        "conversation_id" => context.fetch(:conversation).public_id,
        "turn_id" => context.fetch(:turn).public_id,
      },
      logical_work_id: "prepare-round:#{context.fetch(:workflow_node).public_id}"
    )
    mailbox_item = scenario.fetch(:mailbox_item)
    AgentControl::Poll.call(deployment: context[:deployment], limit: 10)

    AgentControl::HandleAgentProgramReport.call(
      deployment: context[:deployment],
      method_id: "agent_program_completed",
      payload: {
        "mailbox_item_id" => mailbox_item.public_id,
        "logical_work_id" => mailbox_item.logical_work_id,
        "attempt_no" => mailbox_item.attempt_no,
      }
    )

    assert_equal "completed", mailbox_item.reload.status
    assert mailbox_item.completed_at.present?
  end

  test "rejects stale agent program reports after the mailbox lease expires" do
    context = build_agent_control_context!
    leased_at = Time.zone.parse("2026-04-01 10:00:00 UTC")

    mailbox_item = travel_to(leased_at) do
      scenario = MailboxScenarioBuilder.new(self).agent_program_request!(
        context: context,
        request_kind: "prepare_round",
        payload: {
          "workflow_node_id" => context.fetch(:workflow_node).public_id,
          "conversation_id" => context.fetch(:conversation).public_id,
          "turn_id" => context.fetch(:turn).public_id,
        },
        logical_work_id: "prepare-round:#{context.fetch(:workflow_node).public_id}"
      )
      AgentControl::Poll.call(deployment: context[:deployment], limit: 10)
      scenario.fetch(:mailbox_item)
    end

    assert_raises(AgentControl::Report::StaleReportError) do
      AgentControl::HandleAgentProgramReport.call(
        deployment: context[:deployment],
        method_id: "agent_program_completed",
        payload: {
          "mailbox_item_id" => mailbox_item.public_id,
          "logical_work_id" => mailbox_item.logical_work_id,
          "attempt_no" => mailbox_item.attempt_no,
        },
        occurred_at: leased_at + mailbox_item.lease_timeout_seconds.seconds + 1.second
      )
    end

    assert_equal "leased", mailbox_item.reload.status
  end

  test "completes a linked conversation control request when a supervision mailbox request completes" do
    context = build_agent_control_context!
    supervision_session = ConversationSupervisionSession.create!(
      installation: context[:installation],
      target_conversation: context[:conversation],
      initiator: context[:user],
      lifecycle_state: "open",
      responder_strategy: "builtin",
      capability_policy_snapshot: { "supervision_enabled" => true, "side_chat_enabled" => true, "control_enabled" => true },
      last_snapshot_at: Time.current
    )
    control_request = ConversationControlRequest.create!(
      installation: context[:installation],
      conversation_supervision_session: supervision_session,
      target_conversation: context[:conversation],
      request_kind: "request_status_refresh",
      target_kind: "conversation",
      target_public_id: context[:conversation].public_id,
      lifecycle_state: "queued",
      request_payload: {},
      result_payload: {}
    )
    mailbox_item = AgentControl::CreateConversationControlRequest.call(
      conversation_control_request: control_request,
      agent_program_version: context[:deployment],
      request_kind: "supervision_status_refresh",
      payload: {},
      dispatch_deadline_at: 5.minutes.from_now
    )
    AgentControl::Poll.call(deployment: context[:deployment], limit: 10)

    AgentControl::HandleAgentProgramReport.call(
      deployment: context[:deployment],
      method_id: "agent_program_completed",
      payload: {
        "mailbox_item_id" => mailbox_item.public_id,
        "logical_work_id" => mailbox_item.logical_work_id,
        "attempt_no" => mailbox_item.attempt_no,
      }
    )

    assert_equal "completed", control_request.reload.lifecycle_state
    assert_equal mailbox_item.public_id, control_request.result_payload["mailbox_item_id"]
    assert_equal "completed", control_request.result_payload["mailbox_status"]
  end

  test "fails a linked conversation control request when a supervision mailbox request fails" do
    context = build_agent_control_context!
    supervision_session = ConversationSupervisionSession.create!(
      installation: context[:installation],
      target_conversation: context[:conversation],
      initiator: context[:user],
      lifecycle_state: "open",
      responder_strategy: "builtin",
      capability_policy_snapshot: { "supervision_enabled" => true, "side_chat_enabled" => true, "control_enabled" => true },
      last_snapshot_at: Time.current
    )
    control_request = ConversationControlRequest.create!(
      installation: context[:installation],
      conversation_supervision_session: supervision_session,
      target_conversation: context[:conversation],
      request_kind: "send_guidance_to_active_agent",
      target_kind: "conversation",
      target_public_id: context[:conversation].public_id,
      lifecycle_state: "queued",
      request_payload: { "content" => "Stop and summarize." },
      result_payload: {}
    )
    mailbox_item = AgentControl::CreateConversationControlRequest.call(
      conversation_control_request: control_request,
      agent_program_version: context[:deployment],
      request_kind: "supervision_guidance",
      payload: { "content" => "Stop and summarize." },
      dispatch_deadline_at: 5.minutes.from_now
    )
    AgentControl::Poll.call(deployment: context[:deployment], limit: 10)

    AgentControl::HandleAgentProgramReport.call(
      deployment: context[:deployment],
      method_id: "agent_program_failed",
      payload: {
        "mailbox_item_id" => mailbox_item.public_id,
        "logical_work_id" => mailbox_item.logical_work_id,
        "attempt_no" => mailbox_item.attempt_no,
      }
    )

    assert_equal "failed", control_request.reload.lifecycle_state
    assert_equal mailbox_item.public_id, control_request.result_payload["mailbox_item_id"]
    assert_equal "failed", control_request.result_payload["mailbox_status"]
  end
end
