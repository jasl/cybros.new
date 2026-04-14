require "test_helper"

class RuntimeFeatures::FeatureRequestExchangeTest < ActiveSupport::TestCase
  test "creates a mailbox request and returns the completed execute_feature payload" do
    context = build_agent_control_context!
    original_creator = AgentControl::CreateAgentRequest.method(:call)

    AgentControl::CreateAgentRequest.singleton_class.define_method(:call) do |**kwargs|
      mailbox_item = original_creator.call(**kwargs)
      now = Time.current
      mailbox_item.update!(
        status: "leased",
        leased_to_agent_connection: kwargs.fetch(:agent_definition_version).active_agent_connection,
        leased_at: now,
        lease_expires_at: now + mailbox_item.lease_timeout_seconds.seconds
      )
      AgentControlReportReceipt.create!(
        installation: kwargs.fetch(:agent_definition_version).installation,
        agent_connection: kwargs.fetch(:agent_definition_version).active_agent_connection,
        mailbox_item: mailbox_item,
        protocol_message_id: "report-#{SecureRandom.uuid}",
        method_id: "agent_completed",
        logical_work_id: mailbox_item.logical_work_id,
        attempt_no: mailbox_item.attempt_no,
        result_code: "accepted",
        payload: {
          "method_id" => "agent_completed",
          "mailbox_item_id" => mailbox_item.public_id,
          "logical_work_id" => mailbox_item.logical_work_id,
          "attempt_no" => mailbox_item.attempt_no,
          "response_payload" => {
            "status" => "ok",
            "result" => {
              "title" => "Launch checklist plan",
            },
          },
        },
      )
      mailbox_item
    end

    result = RuntimeFeatures::FeatureRequestExchange.new(
      agent_definition_version: context.fetch(:agent_definition_version),
      sleeper: ->(_duration) { },
    ).execute_feature(
      feature_key: "title_bootstrap",
      conversation_id: context.fetch(:workflow_node).conversation.public_id,
      turn_id: context.fetch(:workflow_node).turn.public_id,
      request_payload: {
        "message_content" => "Plan the launch checklist",
      }
    )

    assert_equal "ok", result.fetch("status")
    assert_equal "Launch checklist plan", result.dig("result", "title")
  ensure
    AgentControl::CreateAgentRequest.singleton_class.define_method(:call, original_creator) if original_creator
  end

  test "raises structured failures from terminal execute_feature reports" do
    context = build_agent_control_context!
    original_creator = AgentControl::CreateAgentRequest.method(:call)

    AgentControl::CreateAgentRequest.singleton_class.define_method(:call) do |**kwargs|
      mailbox_item = original_creator.call(**kwargs)
      now = Time.current
      mailbox_item.update!(
        status: "leased",
        leased_to_agent_connection: kwargs.fetch(:agent_definition_version).active_agent_connection,
        leased_at: now,
        lease_expires_at: now + mailbox_item.lease_timeout_seconds.seconds
      )
      AgentControlReportReceipt.create!(
        installation: kwargs.fetch(:agent_definition_version).installation,
        agent_connection: kwargs.fetch(:agent_definition_version).active_agent_connection,
        mailbox_item: mailbox_item,
        protocol_message_id: "report-#{SecureRandom.uuid}",
        method_id: "agent_failed",
        logical_work_id: mailbox_item.logical_work_id,
        attempt_no: mailbox_item.attempt_no,
        result_code: "accepted",
        payload: {
          "method_id" => "agent_failed",
          "mailbox_item_id" => mailbox_item.public_id,
          "logical_work_id" => mailbox_item.logical_work_id,
          "attempt_no" => mailbox_item.attempt_no,
          "error_payload" => {
            "classification" => "runtime",
            "code" => "feature_execution_failed",
            "message" => "title bootstrap crashed",
            "retryable" => false,
          },
        },
      )
      mailbox_item
    end

    error = assert_raises(RuntimeFeatures::FeatureRequestExchange::RequestFailed) do
      RuntimeFeatures::FeatureRequestExchange.new(
        agent_definition_version: context.fetch(:agent_definition_version),
        sleeper: ->(_duration) { },
      ).execute_feature(
        feature_key: "title_bootstrap",
        conversation_id: context.fetch(:workflow_node).conversation.public_id,
        turn_id: context.fetch(:workflow_node).turn.public_id,
        request_payload: {
          "message_content" => "Plan the launch checklist",
        }
      )
    end

    assert_equal "feature_execution_failed", error.code
  ensure
    AgentControl::CreateAgentRequest.singleton_class.define_method(:call, original_creator) if original_creator
  end
end
