require "test_helper"

class AgentApiControlPollTest < ActionDispatch::IntegrationTest
  test "poll returns queued agent-request mailbox items using the shared envelope and leases them to the authenticated agent connection" do
    context = build_agent_control_context!
    scenario = MailboxScenarioBuilder.new(self).agent_request!(
      context: context,
      request_kind: "prepare_round",
      logical_work_id: "prepare-round:#{context[:workflow_node].public_id}",
      payload: {
        "request_kind" => "prepare_round",
        "task" => {
          "kind" => "turn_step",
          "workflow_run_id" => context[:workflow_run].public_id,
          "workflow_node_id" => context[:workflow_node].public_id,
          "conversation_id" => context[:conversation].public_id,
          "turn_id" => context[:turn].public_id,
        },
      }
    )

    post "/agent_api/control/poll",
      params: { limit: 10 },
      headers: agent_api_headers(context[:agent_connection_credential]),
      as: :json

    assert_response :success

    response_body = JSON.parse(response.body)
    item = response_body.fetch("mailbox_items").fetch(0)
    payload = item.fetch("payload")

    assert_equal scenario.fetch(:mailbox_item).public_id, item.fetch("item_id")
    assert_equal "agent_request", item.fetch("item_type")
    assert_equal "agent", item.fetch("control_plane")
    refute item.key?("target_kind")
    refute item.key?("target_ref")
    assert_equal "agent-runtime/2026-04-01", payload.fetch("protocol_version")
    assert_equal "prepare_round", payload.fetch("request_kind")
    assert_equal context[:workflow_run].public_id, payload.dig("task", "workflow_run_id")
    assert_equal context[:turn].public_id, payload.dig("task", "turn_id")
    refute payload.key?("control_plane")
    assert_equal 1, item.fetch("delivery_no")
    assert_equal context[:agent_connection].public_id, scenario.fetch(:mailbox_item).reload.leased_to_agent_connection.public_id
    refute_includes response.body, %("#{context[:workflow_run].id}")
  end

  test "poll does not deliver execution-runtime-plane close work even when the rotated agent definition version shares the execution runtime" do
    context = build_rotated_runtime_context!
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
        "reason_kind" => "turn_interrupted",
      }
    )

    post "/agent_api/control/poll",
      params: { limit: 10 },
      headers: agent_api_headers(context[:replacement_agent_connection_credential]),
      as: :json

    assert_response :success

    response_body = JSON.parse(response.body)
    assert_empty response_body.fetch("mailbox_items")
    assert_nil mailbox_item.reload.leased_to_agent_connection
    assert_nil mailbox_item.leased_to_execution_runtime_connection
  end

  test "poll returns full agent request envelopes when the mailbox row stores a payload document" do
    context = build_agent_control_context!
    mailbox_item = AgentControl::CreateAgentRequest.call(
      agent_definition_version: context.fetch(:agent_definition_version),
      request_kind: "prepare_round",
      payload: {
        "task" => {
          "kind" => "turn_step",
          "turn_id" => context.fetch(:turn).public_id,
          "conversation_id" => context.fetch(:conversation).public_id,
          "workflow_run_id" => context.fetch(:workflow_run).public_id,
          "workflow_node_id" => context.fetch(:workflow_node).public_id,
        },
      },
      logical_work_id: "prepare-round:#{context.fetch(:workflow_node).public_id}",
      dispatch_deadline_at: 5.minutes.from_now
    )

    post "/agent_api/control/poll",
      params: { limit: 10 },
      headers: agent_api_headers(context[:agent_connection_credential]),
      as: :json

    assert_response :success

    item = JSON.parse(response.body).fetch("mailbox_items").find { |entry| entry.fetch("item_id") == mailbox_item.public_id }

    assert item.present?
    assert_equal "agent_request", item.fetch("item_type")
    assert_equal "prepare_round", item.dig("payload", "request_kind")
    assert_equal context[:workflow_node].public_id, item.dig("payload", "task", "workflow_node_id")
    assert_equal context[:turn].public_id, item.dig("payload", "task", "turn_id")
  end

  test "poll returns supervision control request envelopes without leaking internal ids" do
    context = build_agent_control_context!
    supervision_session = ConversationSupervisionSession.create!(
      installation: context[:installation],
      target_conversation: context[:conversation],
      user: context[:conversation].user,
      workspace: context[:conversation].workspace,
      agent: context[:conversation].agent,
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
      user: context[:conversation].user,
      workspace: context[:conversation].workspace,
      agent: context[:conversation].agent,
      request_kind: "request_status_refresh",
      target_kind: "conversation",
      target_public_id: context[:conversation].public_id,
      lifecycle_state: "queued",
      request_payload: {},
      result_payload: {}
    )
    mailbox_item = AgentControl::CreateConversationControlRequest.call(
      conversation_control_request: control_request,
      agent_definition_version: context[:agent_definition_version],
      request_kind: "supervision_status_refresh",
      payload: {},
      dispatch_deadline_at: 5.minutes.from_now
    )

    post "/agent_api/control/poll",
      params: { limit: 10 },
      headers: agent_api_headers(context[:agent_connection_credential]),
      as: :json

    assert_response :success

    item = JSON.parse(response.body).fetch("mailbox_items").find { |entry| entry.fetch("item_id") == mailbox_item.public_id }

    assert item.present?
    assert_equal "agent_request", item.fetch("item_type")
    assert_equal "supervision_status_refresh", item.dig("payload", "request_kind")
    assert_equal control_request.public_id,
      item.dig("payload", "conversation_control", "conversation_control_request_id")
    assert_equal context[:conversation].public_id, item.dig("payload", "conversation_control", "conversation_id")
    assert_equal context[:agent].public_id, item.dig("payload", "runtime_context", "agent_id")
    assert_equal context[:user].public_id, item.dig("payload", "runtime_context", "user_id")
    refute_includes response.body, %("#{control_request.id}")
  end

  test "poll returns execute_tool request envelopes without leaking internal ids" do
    context = build_agent_control_context!
    mailbox_item = AgentControl::CreateAgentRequest.call(
      agent_definition_version: context.fetch(:agent_definition_version),
      request_kind: "execute_tool",
      payload: {
        "task" => {
          "kind" => "turn_step",
          "turn_id" => context.fetch(:turn).public_id,
          "conversation_id" => context.fetch(:conversation).public_id,
          "workflow_run_id" => context.fetch(:workflow_run).public_id,
          "workflow_node_id" => context.fetch(:workflow_node).public_id,
        },
        "tool_call" => {
          "call_id" => "call-poll",
          "tool_name" => "exec_command",
          "arguments" => { "cmd" => "pwd" },
        },
      },
      logical_work_id: "tool-call:#{context.fetch(:workflow_node).public_id}:call-poll",
      dispatch_deadline_at: 5.minutes.from_now
    )

    post "/agent_api/control/poll",
      params: { limit: 10 },
      headers: agent_api_headers(context[:agent_connection_credential]),
      as: :json

    assert_response :success

    item = JSON.parse(response.body).fetch("mailbox_items").find { |entry| entry.fetch("item_id") == mailbox_item.public_id }

    assert item.present?
    assert_equal "agent_request", item.fetch("item_type")
    assert_equal "execute_tool", item.dig("payload", "request_kind")
    assert_equal "call-poll", item.dig("payload", "tool_call", "call_id")
    assert_equal "exec_command", item.dig("payload", "tool_call", "tool_name")
    assert_equal "pwd", item.dig("payload", "tool_call", "arguments", "cmd")
    assert_equal context[:workflow_node].public_id, item.dig("payload", "task", "workflow_node_id")
    assert_equal context[:agent].public_id, item.dig("payload", "runtime_context", "agent_id")
    assert_equal context[:user].public_id, item.dig("payload", "runtime_context", "user_id")
    refute_includes response.body, %("#{context[:workflow_node].id}")
  end

  test "poll does not deliver execution-runtime-plane close requests from the writer path" do
    context = build_rotated_runtime_context!
    process_run = create_process_run!(
      workflow_node: context[:workflow_node],
      execution_runtime: context[:execution_runtime],
      kind: "background_service",
      timeout_seconds: nil
    )
    mailbox_item = MailboxScenarioBuilder.new(self).close_request!(
      context: context,
      resource: process_run,
      reason_kind: "turn_interrupted"
    ).fetch(:mailbox_item)

    post "/agent_api/control/poll",
      params: { limit: 10 },
      headers: agent_api_headers(context[:replacement_agent_connection_credential]),
      as: :json

    assert_response :success

    response_body = JSON.parse(response.body)
    assert_empty response_body.fetch("mailbox_items")
    assert_equal context[:execution_runtime].id, mailbox_item.reload.target_execution_runtime_id
    assert_nil mailbox_item.leased_to_agent_connection
    assert_nil mailbox_item.leased_to_execution_runtime_connection
  end

  test "poll returns mixed mailbox work without control poll query explosion" do
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
          "task" => {
            "kind" => "turn_step",
            "turn_id" => context[:turn].public_id,
            "conversation_id" => context[:conversation].public_id,
            "workflow_run_id" => context[:workflow_run].public_id,
            "workflow_node_id" => context[:workflow_node].public_id,
          },
        }
      )
    end

    queries = capture_sql_queries do
      post "/agent_api/control/poll",
        params: { limit: 10 },
        headers: agent_api_headers(context[:agent_connection_credential]),
        as: :json
    end

    assert_response :success
    assert_operator queries.length, :<=, 43, "Expected agent control poll to stay under 43 SQL queries, got #{queries.length}:\n#{queries.join("\n")}"
  end
end
