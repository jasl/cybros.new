require "test_helper"

class AgentControlPollTest < ActiveSupport::TestCase
  test "leases queued execution assignments on execution-runtime poll and redelivers them after lease expiry" do
    context = build_agent_control_context!
    scenario = MailboxScenarioBuilder.new(self).execution_assignment!(context: context)

    deliveries = AgentControl::Poll.call(execution_runtime_connection: context[:execution_runtime_connection], limit: 10)

    assert_equal [scenario.fetch(:mailbox_item).id], deliveries.map(&:id)
    assert_equal "leased", scenario.fetch(:mailbox_item).reload.status
    assert_equal 1, scenario.fetch(:mailbox_item).delivery_no

    travel 31.seconds do
      redeliveries = AgentControl::Poll.call(execution_runtime_connection: context[:execution_runtime_connection], limit: 10)

      assert_equal [scenario.fetch(:mailbox_item).id], redeliveries.map(&:id)
      assert_equal 2, scenario.fetch(:mailbox_item).reload.delivery_no
    end
  end

  test "agent poll only delivers agent-plane work" do
    context = build_agent_control_context!
    scenario_builder = MailboxScenarioBuilder.new(self)
    request = scenario_builder.agent_request!(
      context: context,
      request_kind: "prepare_round",
      logical_work_id: "prepare-round-agent-only",
      payload: {
        "request_kind" => "prepare_round",
        "task" => {
          "workflow_node_id" => context[:workflow_node].public_id,
          "workflow_run_id" => context[:workflow_run].public_id,
          "conversation_id" => context[:conversation].public_id,
          "turn_id" => context[:turn].public_id,
          "kind" => context[:workflow_node].node_type,
        },
      }
    ).fetch(:mailbox_item)
    process_run = create_process_run!(
      workflow_node: context[:workflow_node],
      execution_runtime: context[:execution_runtime]
    )
    Leases::Acquire.call(
      leased_resource: process_run,
      holder_key: context[:execution_runtime_connection].public_id,
      heartbeat_timeout_seconds: 30
    )
    close_request = scenario_builder.close_request!(context: context, resource: process_run).fetch(:mailbox_item)

    deliveries = AgentControl::Poll.call(agent_definition_version: context[:agent_definition_version], limit: 10)

    assert_equal [request.id], deliveries.map(&:id)
    assert_nil close_request.reload.leased_to_agent_connection
    assert_nil close_request.leased_to_execution_runtime_connection
  end

  test "does not lease execution-runtime-plane work on the agent poll path even when agent hints do not match" do
    context = build_agent_control_context!
    other_agent = create_agent!(installation: context[:installation])
    mailbox_item = create_agent_control_mailbox_item!(
      installation: context[:installation],
      target_agent: other_agent,
      target_execution_runtime: context[:execution_runtime],
      item_type: "resource_close_request",
      control_plane: "execution_runtime",
      payload: {
        "resource_type" => "ProcessRun",
        "resource_id" => "process-#{next_test_sequence}",
        "request_kind" => "turn_interrupt",
        "reason_kind" => "operator_stop",
      }
    )

    deliveries = AgentControl::Poll.call(agent_definition_version: context[:agent_definition_version], limit: 10)

    assert_empty deliveries
    assert_nil mailbox_item.reload.leased_to_agent_connection
    assert_nil mailbox_item.leased_to_execution_runtime_connection
  end

  test "polls mixed agent-plane work without target resolution query explosion" do
    context = build_agent_control_context!
    scenario_builder = MailboxScenarioBuilder.new(self)

    3.times do |index|
      scenario_builder.execution_assignment!(
        context: context,
        task_payload: { "step" => "execute-#{index}" }
      )
    end

    2.times do |index|
      scenario_builder.agent_request!(
        context: context,
        request_kind: "prepare_round",
        logical_work_id: "prepare-round-#{index}",
        payload: {
          "request_kind" => "prepare_round",
          "protocol_version" => "agent-runtime/2026-04-01",
          "task" => {
            "workflow_node_id" => context[:workflow_node].public_id,
            "workflow_run_id" => context[:workflow_run].public_id,
            "conversation_id" => context[:conversation].public_id,
            "turn_id" => context[:turn].public_id,
            "kind" => context[:workflow_node].node_type,
          },
          "runtime_context" => {
            "logical_work_id" => "prepare-round-#{index}",
            "attempt_no" => 1,
            "control_plane" => "agent",
            "agent_definition_version_id" => context[:agent_definition_version].public_id,
          },
        }
      )
    end

    queries = capture_sql_queries do
      AgentControl::Poll.call(
        agent_definition_version: context[:agent_definition_version],
        agent_connection: context[:agent_connection],
        limit: 10
      )
    end

    assert_operator queries.length, :<=, 15, "Expected mixed agent poll to stay under 15 SQL queries, got #{queries.length}:\n#{queries.join("\n")}"
  end

  test "agent poll leases materialized agent-plane work without calling ResolveTargetRuntime" do
    context = build_agent_control_context!
    scenario_builder = MailboxScenarioBuilder.new(self)
    request = scenario_builder.agent_request!(
      context: context,
      request_kind: "prepare_round",
      logical_work_id: "prepare-round-materialized",
      payload: {
        "request_kind" => "prepare_round",
        "task" => {
          "workflow_node_id" => context[:workflow_node].public_id,
          "workflow_run_id" => context[:workflow_run].public_id,
          "conversation_id" => context[:conversation].public_id,
          "turn_id" => context[:turn].public_id,
          "kind" => context[:workflow_node].node_type,
        },
      }
    ).fetch(:mailbox_item)
    original_call = AgentControl::ResolveTargetRuntime.method(:call)

    AgentControl::ResolveTargetRuntime.singleton_class.define_method(:call) do |**|
      raise "ResolveTargetRuntime.call should not be used on the agent poll hot path"
    end

    deliveries = AgentControl::Poll.call(
      agent_definition_version: context[:agent_definition_version],
      agent_connection: context[:agent_connection],
      limit: 10
    )

    assert_equal [request.id], deliveries.map(&:id)
  ensure
    AgentControl::ResolveTargetRuntime.singleton_class.define_method(:call, original_call) if original_call
  end
end
