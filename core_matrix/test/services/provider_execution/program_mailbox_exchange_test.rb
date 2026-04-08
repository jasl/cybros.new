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
            "summary_artifacts" => [],
            "trace" => [],
          },
        }
      )
      mailbox_item
    end

    result = ProviderExecution::ProgramMailboxExchange.new(
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

    assert_equal({ "status" => "ok", "messages" => [], "visible_tool_names" => [], "summary_artifacts" => [], "trace" => [] }, result)
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
        leased_to_agent_session: kwargs.fetch(:agent_program_version).active_agent_session,
        leased_at: now,
        lease_expires_at: now + mailbox_item.lease_timeout_seconds.seconds
      )
      AgentControlReportReceipt.create!(
        installation: kwargs.fetch(:agent_program_version).installation,
        agent_session: kwargs.fetch(:agent_program_version).active_agent_session,
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
      agent_program_version: context.fetch(:deployment),
      sleeper: ->(_duration) { },
    ).execute_program_tool(
      payload: {
        "task" => {
          "conversation_id" => context.fetch(:workflow_node).conversation.public_id,
          "workflow_node_id" => context.fetch(:workflow_node).public_id,
          "turn_id" => context.fetch(:workflow_node).turn.public_id,
          "kind" => "turn_step",
        },
        "program_tool_call" => {
          "call_id" => "tool-call-1",
          "tool_name" => "calculator",
          "arguments" => {},
        },
      }
    )

    assert_equal "failed", result.fetch("status")
    assert_equal "tool_not_allowed", result.dig("failure", "code")
  ensure
    AgentControl::CreateAgentProgramRequest.singleton_class.define_method(:call, original_creator) if original_creator
  end

  test "returns execute_program_tool results from the terminal receipt before tool invocation reconciliation" do
    context = build_agent_control_context!
    implementation_source = ImplementationSource.create!(
      installation: context.fetch(:installation),
      source_kind: "agent",
      source_ref: "agent/browser_open",
      metadata: {}
    )
    tool_definition = ToolDefinition.create!(
      installation: context.fetch(:installation),
      agent_program_version: context.fetch(:deployment),
      tool_name: "browser_open",
      tool_kind: "agent_observation",
      governance_mode: "replaceable",
      policy_payload: {}
    )
    tool_implementation = ToolImplementation.create!(
      installation: context.fetch(:installation),
      tool_definition: tool_definition,
      implementation_source: implementation_source,
      implementation_ref: "agent/browser_open",
      idempotency_policy: "best_effort",
      input_schema: {},
      result_schema: {},
      metadata: {},
      default_for_snapshot: true
    )
    binding = ToolBinding.create!(
      installation: context.fetch(:installation),
      workflow_node: context.fetch(:workflow_node),
      tool_definition: tool_definition,
      tool_implementation: tool_implementation,
      binding_reason: "snapshot_default",
      runtime_state: {}
    )
    invocation = ToolInvocations::Provision.call(
      tool_binding: binding,
      request_payload: { "url" => "http://127.0.0.1:4173" },
      idempotency_key: "tool-call-#{next_test_sequence}"
    ).tool_invocation

    original_creator = AgentControl::CreateAgentProgramRequest.method(:call)

    AgentControl::CreateAgentProgramRequest.singleton_class.define_method(:call) do |**kwargs|
      mailbox_item = original_creator.call(**kwargs)
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
            "program_tool_call" => kwargs.fetch(:payload).fetch("program_tool_call"),
            "result" => {
              "browser_session_id" => "browser-session-1",
              "current_url" => "http://127.0.0.1:4173",
              "content" => "Browser session browser-session-1 opened at http://127.0.0.1:4173.",
            },
            "output_chunks" => [],
            "summary_artifacts" => [],
          },
        }
      )
      mailbox_item
    end

    result = ProviderExecution::ProgramMailboxExchange.new(
      agent_program_version: context.fetch(:deployment),
      sleeper: ->(_duration) { },
    ).execute_program_tool(
      payload: {
        "task" => {
          "conversation_id" => context.fetch(:workflow_node).conversation.public_id,
          "workflow_node_id" => context.fetch(:workflow_node).public_id,
          "turn_id" => context.fetch(:workflow_node).turn.public_id,
          "kind" => "turn_step",
        },
        "program_tool_call" => {
          "call_id" => invocation.idempotency_key,
          "tool_name" => "browser_open",
          "arguments" => { "url" => "http://127.0.0.1:4173" },
        },
        "runtime_resource_refs" => {
          "tool_invocation" => {
            "tool_invocation_id" => invocation.public_id,
          },
        },
      }
    )

    assert_equal "ok", result.fetch("status")
    assert_equal "browser-session-1", result.dig("result", "browser_session_id")
    assert_equal "http://127.0.0.1:4173", result.dig("result", "current_url")
    assert_equal [], result.fetch("output_chunks")
  ensure
    AgentControl::CreateAgentProgramRequest.singleton_class.define_method(:call, original_creator) if original_creator
  end

  test "gives long-running execute_program_tool requests enough time to finish before the mailbox lease expires" do
    context = build_agent_control_context!
    original_creator = AgentControl::CreateAgentProgramRequest.method(:call)
    captured_kwargs = nil
    requested_at = Time.zone.parse("2026-03-31 10:00:00 UTC")

    travel_to(requested_at) do
      AgentControl::CreateAgentProgramRequest.singleton_class.define_method(:call) do |**kwargs|
        captured_kwargs = kwargs
        mailbox_item = original_creator.call(**kwargs)
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
              "result" => {},
              "output_chunks" => [],
              "summary_artifacts" => [],
            },
          }
        )
        mailbox_item
      end

      ProviderExecution::ProgramMailboxExchange.new(
        agent_program_version: context.fetch(:deployment),
        sleeper: ->(_duration) { },
      ).execute_program_tool(
        payload: {
          "task" => {
            "conversation_id" => context.fetch(:workflow_node).conversation.public_id,
            "workflow_node_id" => context.fetch(:workflow_node).public_id,
            "turn_id" => context.fetch(:workflow_node).turn.public_id,
            "kind" => "turn_step",
          },
          "program_tool_call" => {
            "call_id" => "tool-call-1",
            "tool_name" => "calculator",
            "arguments" => {
              "timeout_seconds" => 120,
            },
          },
        }
      )
    end

    assert_operator captured_kwargs.fetch(:dispatch_deadline_at), :>, requested_at + 120.seconds
    assert_operator captured_kwargs.fetch(:lease_timeout_seconds), :>, 120
  ensure
    AgentControl::CreateAgentProgramRequest.singleton_class.define_method(:call, original_creator) if original_creator
  end

  test "times out when no terminal report arrives" do
    context = build_agent_control_context!

    error = assert_raises(ProviderExecution::ProgramMailboxExchange::TimeoutError) do
      ProviderExecution::ProgramMailboxExchange.new(
        agent_program_version: context.fetch(:deployment),
        timeout: 0.001,
        poll_interval: 0.0,
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

    assert_equal "mailbox_timeout", error.code
  end

  test "uses capped exponential backoff when polling for terminal receipts" do
    exchange = ProviderExecution::ProgramMailboxExchange.new(
      agent_program_version: build_agent_control_context!.fetch(:deployment),
      poll_interval: 0.05,
      sleeper: ->(_duration) { },
    )

    assert_in_delta 0.05, exchange.send(:poll_interval_for_attempt, 1), 0.0001
    assert_in_delta 0.1, exchange.send(:poll_interval_for_attempt, 2), 0.0001
    assert_in_delta 0.2, exchange.send(:poll_interval_for_attempt, 3), 0.0001
    assert_in_delta 0.4, exchange.send(:poll_interval_for_attempt, 4), 0.0001
    assert_in_delta 0.8, exchange.send(:poll_interval_for_attempt, 5), 0.0001
    assert_in_delta 0.8, exchange.send(:poll_interval_for_attempt, 6), 0.0001
  end

  test "keeps zero poll intervals disabled for deterministic tests" do
    exchange = ProviderExecution::ProgramMailboxExchange.new(
      agent_program_version: build_agent_control_context!.fetch(:deployment),
      poll_interval: 0.0,
      sleeper: ->(_duration) { },
    )

    assert_equal 0.0, exchange.send(:poll_interval_for_attempt, 1)
    assert_equal 0.0, exchange.send(:poll_interval_for_attempt, 10)
  end

  test "sees terminal reports that arrive after the first poll even when query cache is enabled" do
    context = build_agent_control_context!
    original_creator = AgentControl::CreateAgentProgramRequest.method(:call)
    original_find_by = AgentControlReportReceipt.method(:find_by)
    original_uncached = AgentControlReportReceipt.method(:uncached)
    mailbox_item = nil
    uncached_depth = 0

    AgentControl::CreateAgentProgramRequest.singleton_class.define_method(:call) do |**kwargs|
      mailbox_item = original_creator.call(**kwargs)
    end

    AgentControlReportReceipt.singleton_class.define_method(:uncached) do |&block|
      uncached_depth += 1
      block.call
    ensure
      uncached_depth -= 1
    end

    AgentControlReportReceipt.singleton_class.define_method(:find_by) do |**kwargs|
      if uncached_depth.zero?
        nil
      else
        original_find_by.call(**kwargs)
      end
    end

    sleep_calls = 0
    sleeper = lambda do |_duration|
      sleep_calls += 1
      next unless sleep_calls == 1

      now = Time.current
      mailbox_item.update!(
        status: "leased",
        leased_to_agent_session: context.fetch(:agent_session),
        leased_at: now,
        lease_expires_at: now + mailbox_item.lease_timeout_seconds.seconds
      )
      AgentControlReportReceipt.create!(
        installation: context.fetch(:deployment).installation,
        agent_session: context.fetch(:agent_session),
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
              "summary_artifacts" => [],
              "trace" => [],
            },
          }
        )
    end

    result = nil
    result = ProviderExecution::ProgramMailboxExchange.new(
      agent_program_version: context.fetch(:deployment),
      timeout: 0.1,
      poll_interval: 0.0,
      sleeper: sleeper,
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

    assert_equal({ "status" => "ok", "messages" => [], "visible_tool_names" => [], "summary_artifacts" => [], "trace" => [] }, result)
    assert_operator sleep_calls, :>=, 1
  ensure
    AgentControl::CreateAgentProgramRequest.singleton_class.define_method(:call, original_creator) if original_creator
    AgentControlReportReceipt.singleton_class.define_method(:find_by, original_find_by) if original_find_by
    AgentControlReportReceipt.singleton_class.define_method(:uncached, original_uncached) if original_uncached
  end
end
