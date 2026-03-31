require "test_helper"

class ProviderExecution::ProgramMailboxExchangeTest < ActiveSupport::TestCase
  test "creates a mailbox request and returns the completed prepare_round payload" do
    context = build_agent_control_context!
    original_creator = AgentControl::CreateAgentProgramRequest.method(:call)

    AgentControl::CreateAgentProgramRequest.singleton_class.define_method(:call) do |**kwargs|
      mailbox_item = original_creator.call(**kwargs)
      now = Time.current
      mailbox_item.update!(
        status: "leased",
        leased_to_agent_deployment: kwargs.fetch(:agent_deployment),
        leased_at: now,
        lease_expires_at: now + mailbox_item.lease_timeout_seconds.seconds
      )
      AgentControlReportReceipt.create!(
        installation: kwargs.fetch(:agent_deployment).installation,
        agent_deployment: kwargs.fetch(:agent_deployment),
        mailbox_item: mailbox_item,
        protocol_message_id: "report-#{SecureRandom.uuid}",
        method_id: "agent_program_completed",
        logical_work_id: mailbox_item.logical_work_id,
        attempt_no: mailbox_item.attempt_no,
        result_code: "accepted",
        payload: {
          "method_id" => "agent_program_completed",
          "mailbox_item_id" => mailbox_item.public_id,
          "logical_work_id" => mailbox_item.logical_work_id,
          "attempt_no" => mailbox_item.attempt_no,
          "response_payload" => {
            "messages" => [],
            "program_tools" => [],
          },
        }
      )
      mailbox_item
    end

    result = ProviderExecution::ProgramMailboxExchange.new(
      agent_deployment: context.fetch(:deployment),
      sleeper: ->(_duration) {}
    ).prepare_round(payload: { "workflow_node_id" => context.fetch(:workflow_node).public_id })

    assert_equal({ "messages" => [], "program_tools" => [] }, result)
  ensure
    AgentControl::CreateAgentProgramRequest.singleton_class.define_method(:call, original_creator) if original_creator
  end

  test "returns structured execute_program_tool failures from the terminal mailbox report" do
    context = build_agent_control_context!
    original_creator = AgentControl::CreateAgentProgramRequest.method(:call)

    AgentControl::CreateAgentProgramRequest.singleton_class.define_method(:call) do |**kwargs|
      mailbox_item = original_creator.call(**kwargs)
      now = Time.current
      mailbox_item.update!(
        status: "leased",
        leased_to_agent_deployment: kwargs.fetch(:agent_deployment),
        leased_at: now,
        lease_expires_at: now + mailbox_item.lease_timeout_seconds.seconds
      )
      AgentControlReportReceipt.create!(
        installation: kwargs.fetch(:agent_deployment).installation,
        agent_deployment: kwargs.fetch(:agent_deployment),
        mailbox_item: mailbox_item,
        protocol_message_id: "report-#{SecureRandom.uuid}",
        method_id: "agent_program_failed",
        logical_work_id: mailbox_item.logical_work_id,
        attempt_no: mailbox_item.attempt_no,
        result_code: "accepted",
        payload: {
          "method_id" => "agent_program_failed",
          "mailbox_item_id" => mailbox_item.public_id,
          "logical_work_id" => mailbox_item.logical_work_id,
          "attempt_no" => mailbox_item.attempt_no,
          "error_payload" => {
            "classification" => "authorization",
            "code" => "tool_not_allowed",
            "message" => "calculator is not visible",
            "retryable" => false,
          },
        }
      )
      mailbox_item
    end

    result = ProviderExecution::ProgramMailboxExchange.new(
      agent_deployment: context.fetch(:deployment),
      sleeper: ->(_duration) {}
    ).execute_program_tool(
      payload: {
        "workflow_node_id" => context.fetch(:workflow_node).public_id,
        "tool_call_id" => "tool-call-1",
      }
    )

    assert_equal "failed", result.fetch("status")
    assert_equal "tool_not_allowed", result.dig("error", "code")
  ensure
    AgentControl::CreateAgentProgramRequest.singleton_class.define_method(:call, original_creator) if original_creator
  end

  test "times out when no terminal report arrives" do
    context = build_agent_control_context!

    error = assert_raises(ProviderExecution::ProgramMailboxExchange::TimeoutError) do
      ProviderExecution::ProgramMailboxExchange.new(
        agent_deployment: context.fetch(:deployment),
        timeout: 0.001,
        poll_interval: 0.0,
        sleeper: ->(_duration) {}
      ).prepare_round(payload: { "workflow_node_id" => context.fetch(:workflow_node).public_id })
    end

    assert_equal "mailbox_timeout", error.code
  end
end
