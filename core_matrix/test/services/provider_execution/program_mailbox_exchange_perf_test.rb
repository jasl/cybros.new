require "test_helper"

class ProviderExecution::ProgramMailboxExchangePerfTest < ActiveSupport::TestCase
  test "publishes mailbox exchange wait event on successful prepare_round completion" do
    context = build_agent_control_context!
    original_creator = AgentControl::CreateAgentProgramRequest.method(:call)
    events = []
    created_mailbox_item = nil

    AgentControl::CreateAgentProgramRequest.singleton_class.define_method(:call) do |**kwargs|
      mailbox_item = original_creator.call(**kwargs)
      created_mailbox_item = mailbox_item
      now = Time.current
      mailbox_item.update!(
        status: "leased",
        leased_to_agent_session: kwargs.fetch(:agent_program_version).active_agent_session,
        leased_at: now,
        lease_expires_at: now + mailbox_item.lease_timeout_seconds.seconds
      )
      AgentControlReportReceipt.create!(
        installation: kwargs.fetch(:agent_program_version).installation,
        agent_session: kwargs.fetch(:agent_program_version).active_agent_session,
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
            "status" => "ok",
            "messages" => [],
            "visible_tool_names" => [],
          },
        }
      )
      mailbox_item
    end

    ActiveSupport::Notifications.subscribed(->(*args) { events << args.last }, "perf.provider_execution.program_mailbox_exchange_wait") do
      ProviderExecution::ProgramMailboxExchange.new(
        agent_program_version: context.fetch(:deployment),
        sleeper: ->(_duration) { },
      ).prepare_round(
        payload: {
          "task" => {
            "conversation_id" => context.fetch(:workflow_node).conversation.public_id,
            "workflow_node_id" => context.fetch(:workflow_node).public_id,
            "turn_id" => context.fetch(:workflow_node).turn.public_id,
            "kind" => "turn_step",
          },
        }
      )
    end

    assert_equal 1, events.length
    assert_equal true, events.first.fetch("success")
    assert_equal "prepare_round", events.first.fetch("request_kind")
    assert_equal created_mailbox_item.public_id, events.first.fetch("mailbox_item_public_id")
  ensure
    AgentControl::CreateAgentProgramRequest.singleton_class.define_method(:call, original_creator) if original_creator
  end

  test "publishes mailbox exchange wait event when a deferred request times out on rerun" do
    context = build_agent_control_context!
    original_creator = AgentControl::CreateAgentProgramRequest.method(:call)
    events = []
    created_mailbox_item = nil

    AgentControl::CreateAgentProgramRequest.singleton_class.define_method(:call) do |**kwargs|
      created_mailbox_item = original_creator.call(**kwargs)
    end

    assert_raises(ProviderExecution::ProgramMailboxExchange::PendingResponse) do
      ActiveSupport::Notifications.subscribed(->(*args) { events << args.last }, "perf.provider_execution.program_mailbox_exchange_wait") do
        ProviderExecution::ProgramMailboxExchange.new(
          agent_program_version: context.fetch(:deployment),
          prepare_round_timeout: 0.001.seconds,
          sleeper: ->(_duration) { },
        ).prepare_round(
          payload: {
            "task" => {
              "conversation_id" => context.fetch(:workflow_node).conversation.public_id,
              "workflow_node_id" => context.fetch(:workflow_node).public_id,
              "turn_id" => context.fetch(:workflow_node).turn.public_id,
              "kind" => "turn_step",
            },
          }
        )
      end
    end

    error = assert_raises(ProviderExecution::ProgramMailboxExchange::TimeoutError) do
      ActiveSupport::Notifications.subscribed(->(*args) { events << args.last }, "perf.provider_execution.program_mailbox_exchange_wait") do
        ProviderExecution::ProgramMailboxExchange.new(
          agent_program_version: context.fetch(:deployment),
          prepare_round_timeout: 0.001.seconds,
          sleeper: ->(_duration) { },
        ).prepare_round(
          payload: {
            "task" => {
              "conversation_id" => context.fetch(:workflow_node).conversation.public_id,
              "workflow_node_id" => context.fetch(:workflow_node).public_id,
              "turn_id" => context.fetch(:workflow_node).turn.public_id,
              "kind" => "turn_step",
            },
          }
        )
      end
    end

    assert_equal "mailbox_timeout", error.code
    assert_equal 1, events.length
    assert_equal false, events.first.fetch("success")
    assert_equal "prepare_round", events.first.fetch("request_kind")
    assert_equal created_mailbox_item.public_id, events.first.fetch("mailbox_item_public_id")
  ensure
    AgentControl::CreateAgentProgramRequest.singleton_class.define_method(:call, original_creator) if original_creator
  end
end
