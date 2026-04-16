require "test_helper"

class ProviderExecution::AgentRequestExchangeTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "creates a mailbox request and returns the completed prepare_round payload" do
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
            "messages" => [],
            "visible_tool_names" => [],
            "summary_artifacts" => [],
            "trace" => [],
          },
        }
      )
      mailbox_item
    end

    result = ProviderExecution::AgentRequestExchange.new(
      agent_definition_version: context.fetch(:agent_definition_version),
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
    AgentControl::CreateAgentRequest.singleton_class.define_method(:call, original_creator) if original_creator
  end

  test "returns structured execute_tool failures from the terminal mailbox report" do
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
            "classification" => "authorization",
            "code" => "tool_not_allowed",
            "message" => "compact_context is not visible",
            "retryable" => false,
          },
        }
      )
      mailbox_item
    end

    result = ProviderExecution::AgentRequestExchange.new(
      agent_definition_version: context.fetch(:agent_definition_version),
      sleeper: ->(_duration) { },
    ).execute_tool(
      payload: {
        "task" => {
          "conversation_id" => context.fetch(:workflow_node).conversation.public_id,
          "workflow_node_id" => context.fetch(:workflow_node).public_id,
          "turn_id" => context.fetch(:workflow_node).turn.public_id,
          "kind" => "turn_step",
        },
        "tool_call" => {
          "call_id" => "tool-call-1",
          "tool_name" => "compact_context",
          "arguments" => {},
        },
      }
    )

    assert_equal "failed", result.fetch("status")
    assert_equal "tool_not_allowed", result.dig("failure", "code")
  ensure
    AgentControl::CreateAgentRequest.singleton_class.define_method(:call, original_creator) if original_creator
  end

  test "returns execute_tool results from the terminal receipt before tool invocation reconciliation" do
    context = build_agent_control_context!
    implementation_source = ImplementationSource.create!(
      installation: context.fetch(:installation),
      source_kind: "agent",
      source_ref: "agent/browser_open",
      metadata: {}
    )
    tool_definition = ToolDefinition.create!(
      installation: context.fetch(:installation),
      agent_definition_version: context.fetch(:agent_definition_version),
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
            "tool_call" => kwargs.fetch(:payload).fetch("tool_call"),
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

    result = ProviderExecution::AgentRequestExchange.new(
      agent_definition_version: context.fetch(:agent_definition_version),
      sleeper: ->(_duration) { },
    ).execute_tool(
      payload: {
        "task" => {
          "conversation_id" => context.fetch(:workflow_node).conversation.public_id,
          "workflow_node_id" => context.fetch(:workflow_node).public_id,
          "turn_id" => context.fetch(:workflow_node).turn.public_id,
          "kind" => "turn_step",
        },
        "tool_call" => {
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
    AgentControl::CreateAgentRequest.singleton_class.define_method(:call, original_creator) if original_creator
  end

  test "gives long-running execute_tool requests enough time to finish before the mailbox lease expires" do
    context = build_agent_control_context!
    original_creator = AgentControl::CreateAgentRequest.method(:call)
    captured_kwargs = nil
    requested_at = Time.zone.parse("2026-03-31 10:00:00 UTC")

    travel_to(requested_at) do
      AgentControl::CreateAgentRequest.singleton_class.define_method(:call) do |**kwargs|
        captured_kwargs = kwargs
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
              "result" => {},
              "output_chunks" => [],
              "summary_artifacts" => [],
            },
          }
        )
        mailbox_item
      end

      ProviderExecution::AgentRequestExchange.new(
        agent_definition_version: context.fetch(:agent_definition_version),
        sleeper: ->(_duration) { },
      ).execute_tool(
        payload: {
          "task" => {
            "conversation_id" => context.fetch(:workflow_node).conversation.public_id,
            "workflow_node_id" => context.fetch(:workflow_node).public_id,
            "turn_id" => context.fetch(:workflow_node).turn.public_id,
            "kind" => "turn_step",
          },
          "tool_call" => {
            "call_id" => "tool-call-1",
            "tool_name" => "compact_context",
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
    AgentControl::CreateAgentRequest.singleton_class.define_method(:call, original_creator) if original_creator
  end

  test "times out on rerun when no terminal report arrives before the deferred request deadline" do
    context = build_agent_control_context!

    assert_raises(ProviderExecution::AgentRequestExchange::PendingResponse) do
      ProviderExecution::AgentRequestExchange.new(
        agent_definition_version: context.fetch(:agent_definition_version),
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

    error = assert_raises(ProviderExecution::AgentRequestExchange::TimeoutError) do
      ProviderExecution::AgentRequestExchange.new(
        agent_definition_version: context.fetch(:agent_definition_version),
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

  test "rerun while pending re-blocks the workflow node to preserve the pending wait state" do
    context = build_agent_control_context!
    workflow_node = context.fetch(:workflow_node)
    original_blocker = Workflows::BlockNodeForAgentRequest.method(:call)
    block_calls = []
    payload = {
      "task" => {
        "conversation_id" => workflow_node.conversation.public_id,
        "workflow_node_id" => workflow_node.public_id,
        "turn_id" => workflow_node.turn.public_id,
        "kind" => "turn_step",
      },
    }

    Workflows::BlockNodeForAgentRequest.singleton_class.define_method(:call) do |**kwargs|
      block_calls << kwargs.slice(:request_kind, :logical_work_id)
      original_blocker.call(**kwargs)
    end

    exchange = ProviderExecution::AgentRequestExchange.new(
      agent_definition_version: context.fetch(:agent_definition_version),
      timeout: 30.seconds,
      poll_interval: 0.0,
      sleeper: ->(_duration) { },
    )

    assert_raises(ProviderExecution::AgentRequestExchange::PendingResponse) do
      exchange.prepare_round(payload: payload)
    end
    assert_equal 1, block_calls.length

    assert_raises(ProviderExecution::AgentRequestExchange::PendingResponse) do
      exchange.prepare_round(payload: payload)
    end
    assert_equal 2, block_calls.length
    assert_equal "waiting", workflow_node.reload.lifecycle_state
    assert_equal "waiting", workflow_node.workflow_run.reload.wait_state
  ensure
    Workflows::BlockNodeForAgentRequest.singleton_class.define_method(:call, original_blocker) if original_blocker
  end

  test "blocks the workflow node and resumes from a terminal receipt instead of synchronously polling" do
    context = build_agent_control_context!
    workflow_node = context.fetch(:workflow_node)
    workflow_run = context.fetch(:workflow_run)

    assert_raises(ProviderExecution::AgentRequestExchange::PendingResponse) do
      ProviderExecution::AgentRequestExchange.new(
        agent_definition_version: context.fetch(:agent_definition_version),
        timeout: 0.001,
        poll_interval: 0.0,
        sleeper: ->(_duration) { },
      ).prepare_round(
        payload: {
          "task" => {
            "conversation_id" => workflow_node.conversation.public_id,
            "workflow_node_id" => workflow_node.public_id,
            "turn_id" => workflow_node.turn.public_id,
            "kind" => "turn_step",
          },
        }
      )
    end

    assert_enqueued_with(
      job: Workflows::ResumeBlockedStepJob,
      args: ->(job_args) do
        job_args.first == workflow_run.public_id &&
          job_args.second.is_a?(Hash) &&
          job_args.second[:expected_waiting_since_at_iso8601] == workflow_run.reload.waiting_since_at&.utc&.iso8601(6)
      end
    )

    mailbox_item = AgentControlMailboxItem.find_by!(
      workflow_node: workflow_node,
      item_type: "agent_request",
      logical_work_id: "prepare-round:#{workflow_node.public_id}"
    )

    assert_equal "waiting", workflow_node.reload.lifecycle_state
    assert_equal "waiting", workflow_run.reload.wait_state
    assert_equal "agent_request", workflow_run.wait_reason_kind
    assert_equal mailbox_item.public_id, workflow_run.wait_reason_payload.fetch("mailbox_item_id")
    assert_equal(
      {
        "mailbox_item_id" => mailbox_item.public_id,
        "logical_work_id" => mailbox_item.logical_work_id,
        "request_kind" => "prepare_round",
      },
      workflow_node.reload.metadata.fetch("agent_request_exchange")
    )

    now = Time.current
    mailbox_item.update!(
      status: "completed",
      completed_at: now
    )
    AgentControlReportReceipt.create!(
      installation: context.fetch(:agent_definition_version).installation,
      agent_connection: context.fetch(:agent_connection),
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
          "messages" => [],
          "visible_tool_names" => [],
          "summary_artifacts" => [],
          "trace" => [],
        },
      }
    )
    Workflows::ResumeBlockedStep.call(workflow_run: workflow_run)

    result = ProviderExecution::AgentRequestExchange.new(
      agent_definition_version: context.fetch(:agent_definition_version),
      timeout: 0.001,
      poll_interval: 0.0,
      sleeper: ->(_duration) { },
    ).prepare_round(
      payload: {
        "task" => {
          "conversation_id" => workflow_node.conversation.public_id,
          "workflow_node_id" => workflow_node.public_id,
          "turn_id" => workflow_node.turn.public_id,
          "kind" => "turn_step",
        },
      }
    )

    assert_equal [], result.fetch("messages")
    assert_nil workflow_node.reload.metadata["agent_request_exchange"]
  end

  test "uses capped exponential backoff when polling for terminal receipts" do
    exchange = ProviderExecution::AgentRequestExchange.new(
      agent_definition_version: build_agent_control_context!.fetch(:agent_definition_version),
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
    exchange = ProviderExecution::AgentRequestExchange.new(
      agent_definition_version: build_agent_control_context!.fetch(:agent_definition_version),
      poll_interval: 0.0,
      sleeper: ->(_duration) { },
    )

    assert_equal 0.0, exchange.send(:poll_interval_for_attempt, 1)
    assert_equal 0.0, exchange.send(:poll_interval_for_attempt, 10)
  end

  test "sees terminal reports that arrive after the initial deferred request even when query cache is enabled" do
    context = build_agent_control_context!
    original_creator = AgentControl::CreateAgentRequest.method(:call)
    original_find_by = AgentControlReportReceipt.method(:find_by)
    original_uncached = AgentControlReportReceipt.method(:uncached)
    mailbox_item = nil
    uncached_depth = 0

    AgentControl::CreateAgentRequest.singleton_class.define_method(:call) do |**kwargs|
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

    assert_raises(ProviderExecution::AgentRequestExchange::PendingResponse) do
      ProviderExecution::AgentRequestExchange.new(
        agent_definition_version: context.fetch(:agent_definition_version),
        timeout: 0.1,
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

    now = Time.current
    mailbox_item.update!(
      status: "completed",
      leased_to_agent_connection: context.fetch(:agent_connection),
      leased_at: now,
      lease_expires_at: now + mailbox_item.lease_timeout_seconds.seconds,
      completed_at: now
    )
    AgentControlReportReceipt.create!(
      installation: context.fetch(:agent_definition_version).installation,
      agent_connection: context.fetch(:agent_connection),
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
          "messages" => [],
          "visible_tool_names" => [],
          "summary_artifacts" => [],
          "trace" => [],
        },
      }
    )

    result = ProviderExecution::AgentRequestExchange.new(
      agent_definition_version: context.fetch(:agent_definition_version),
      timeout: 0.1,
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

    assert_equal({ "status" => "ok", "messages" => [], "visible_tool_names" => [], "summary_artifacts" => [], "trace" => [] }, result)
  ensure
    AgentControl::CreateAgentRequest.singleton_class.define_method(:call, original_creator) if original_creator
    AgentControlReportReceipt.singleton_class.define_method(:find_by, original_find_by) if original_find_by
    AgentControlReportReceipt.singleton_class.define_method(:uncached, original_uncached) if original_uncached
  end
end
