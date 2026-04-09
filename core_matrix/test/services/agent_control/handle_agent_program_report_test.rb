require "test_helper"

class AgentControl::HandleAgentProgramReportTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

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
        "response_payload" => {
          "status" => "ok",
          "control_outcome" => {
            "outcome_kind" => "status_refresh_acknowledged",
            "conversation_control_request_id" => control_request.public_id,
          },
        },
      }
    )

    assert_equal "completed", control_request.reload.lifecycle_state
    assert_equal mailbox_item.public_id, control_request.result_payload["mailbox_item_id"]
    assert_equal "completed", control_request.result_payload["mailbox_status"]
    assert_equal "status_refresh_acknowledged",
      control_request.result_payload.dig("response_payload", "control_outcome", "outcome_kind")
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
        "error_payload" => {
          "classification" => "runtime",
          "code" => "guidance_delivery_failed",
          "message" => "guidance could not be delivered",
          "retryable" => false,
        },
      }
    )

    assert_equal "failed", control_request.reload.lifecycle_state
    assert_equal mailbox_item.public_id, control_request.result_payload["mailbox_item_id"]
    assert_equal "failed", control_request.result_payload["mailbox_status"]
    assert_equal "guidance_delivery_failed", control_request.result_payload.dig("error_payload", "code")
  end

  test "completed supervision guidance reports become durable guidance for the next round" do
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
      request_payload: { "content" => "Stop and summarize the blocker before coding." },
      result_payload: {}
    )
    mailbox_item = AgentControl::CreateConversationControlRequest.call(
      conversation_control_request: control_request,
      agent_program_version: context[:deployment],
      request_kind: "supervision_guidance",
      payload: { "content" => "Stop and summarize the blocker before coding." },
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
        "response_payload" => {
          "status" => "ok",
          "control_outcome" => {
            "outcome_kind" => "guidance_acknowledged",
            "conversation_control_request_id" => control_request.public_id,
            "conversation_id" => context[:conversation].public_id,
            "target_kind" => "conversation",
            "target_public_id" => context[:conversation].public_id,
            "content" => "Stop and summarize the blocker before coding.",
          },
        },
      }
    )

    projection = ConversationControl::BuildGuidanceProjection.call(
      conversation: context[:conversation]
    )

    assert_equal control_request.public_id, projection.dig("latest_guidance", "conversation_control_request_id")
    assert_equal "Stop and summarize the blocker before coding.", projection.dig("latest_guidance", "content")
  end

  test "enqueues a blocked workflow resume when a terminal agent program report arrives" do
    context = build_agent_control_context!
    mailbox_item = AgentControl::CreateAgentProgramRequest.call(
      agent_program_version: context.fetch(:deployment),
      request_kind: "prepare_round",
      payload: {
        "task" => {
          "workflow_node_id" => context.fetch(:workflow_node).public_id,
          "conversation_id" => context.fetch(:conversation).public_id,
          "turn_id" => context.fetch(:turn).public_id,
          "kind" => "turn_step",
        },
      },
      logical_work_id: "prepare-round:#{context.fetch(:workflow_node).public_id}",
      dispatch_deadline_at: 5.minutes.from_now
    )
    AgentControl::Poll.call(deployment: context.fetch(:deployment), limit: 10)

    context.fetch(:workflow_node).update!(
      lifecycle_state: "waiting",
      started_at: 1.minute.ago,
      metadata: {
        "program_mailbox_exchange" => {
          "mailbox_item_id" => mailbox_item.public_id,
          "logical_work_id" => mailbox_item.logical_work_id,
          "request_kind" => "prepare_round",
        },
      }
    )
    context.fetch(:turn).update!(lifecycle_state: "waiting")
    context.fetch(:workflow_run).update!(
      wait_state: "waiting",
      wait_reason_kind: "agent_program_request",
      wait_reason_payload: {
        "mailbox_item_id" => mailbox_item.public_id,
        "logical_work_id" => mailbox_item.logical_work_id,
        "request_kind" => "prepare_round",
      },
      waiting_since_at: Time.current,
      blocking_resource_type: "WorkflowNode",
      blocking_resource_id: context.fetch(:workflow_node).public_id
    )

    assert_enqueued_with(job: Workflows::ResumeBlockedStepJob, args: [context.fetch(:workflow_run).public_id]) do
      AgentControl::HandleAgentProgramReport.call(
        deployment: context.fetch(:deployment),
        method_id: "agent_program_completed",
        payload: {
          "mailbox_item_id" => mailbox_item.public_id,
          "logical_work_id" => mailbox_item.logical_work_id,
          "attempt_no" => mailbox_item.attempt_no,
          "response_payload" => {
            "status" => "ok",
            "messages" => [],
            "visible_tool_names" => [],
            "summary_artifacts" => [],
            "trace" => [],
          },
        }
      )
    end
  end
end
