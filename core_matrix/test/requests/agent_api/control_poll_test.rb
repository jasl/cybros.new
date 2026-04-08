require "test_helper"

class AgentApiControlPollTest < ActionDispatch::IntegrationTest
  test "poll returns queued mailbox items using the shared envelope and leases them to the authenticated deployment" do
    context = build_agent_control_context!
    scenario = MailboxScenarioBuilder.new(self).execution_assignment!(
      context: context,
      task_payload: {
        "turn_id" => context[:turn].public_id,
        "workflow_run_id" => context[:workflow_run].public_id,
      }
    )

    post "/agent_api/control/poll",
      params: { limit: 10 },
      headers: agent_api_headers(context[:machine_credential]),
      as: :json

    assert_response :success

    response_body = JSON.parse(response.body)
    item = response_body.fetch("mailbox_items").fetch(0)
    payload = item.fetch("payload")

    assert_equal scenario.fetch(:mailbox_item).public_id, item.fetch("item_id")
    assert_equal "execution_assignment", item.fetch("item_type")
    assert_equal "program", item.fetch("control_plane")
    refute item.key?("target_kind")
    refute item.key?("target_ref")
    assert_equal "agent-program/2026-04-01", payload.fetch("protocol_version")
    assert_equal "execution_assignment", payload.fetch("request_kind")
    assert_equal context[:workflow_run].public_id, payload.dig("task", "workflow_run_id")
    assert_equal context[:turn].public_id, payload.dig("task", "turn_id")
    refute payload.key?("control_plane")
    assert_equal 1, item.fetch("delivery_no")
    refute_includes response.body, %("#{context[:workflow_run].id}")
  end

  test "poll does not deliver executor-plane close work even when the rotated program version shares the executor program" do
    context = build_rotated_runtime_context!
    other_agent_program = create_agent_program!(installation: context[:installation])
    mailbox_item = create_agent_control_mailbox_item!(
      installation: context[:installation],
      target_agent_program: other_agent_program,
      target_executor_program: context[:executor_program],
      item_type: "resource_close_request",
      control_plane: "executor",
      payload: {
        "resource_type" => "ProcessRun",
        "resource_id" => "process-#{next_test_sequence}",
        "request_kind" => "turn_interrupt",
        "reason_kind" => "turn_interrupted",
      }
    )

    post "/agent_api/control/poll",
      params: { limit: 10 },
      headers: agent_api_headers(context[:replacement_machine_credential]),
      as: :json

    assert_response :success

    response_body = JSON.parse(response.body)
    assert_empty response_body.fetch("mailbox_items")
    assert_nil mailbox_item.reload.leased_to_agent_session
    assert_nil mailbox_item.leased_to_executor_session
  end

  test "poll returns full agent program request envelopes when the mailbox row stores a payload document" do
    context = build_agent_control_context!
    mailbox_item = AgentControl::CreateAgentProgramRequest.call(
      agent_program_version: context.fetch(:deployment),
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
      headers: agent_api_headers(context[:machine_credential]),
      as: :json

    assert_response :success

    item = JSON.parse(response.body).fetch("mailbox_items").find { |entry| entry.fetch("item_id") == mailbox_item.public_id }

    assert item.present?
    assert_equal "agent_program_request", item.fetch("item_type")
    assert_equal "prepare_round", item.dig("payload", "request_kind")
    assert_equal context[:workflow_node].public_id, item.dig("payload", "task", "workflow_node_id")
    assert_equal context[:turn].public_id, item.dig("payload", "task", "turn_id")
  end

  test "poll returns supervision control request envelopes without leaking internal ids" do
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

    post "/agent_api/control/poll",
      params: { limit: 10 },
      headers: agent_api_headers(context[:machine_credential]),
      as: :json

    assert_response :success

    item = JSON.parse(response.body).fetch("mailbox_items").find { |entry| entry.fetch("item_id") == mailbox_item.public_id }

    assert item.present?
    assert_equal "agent_program_request", item.fetch("item_type")
    assert_equal "supervision_status_refresh", item.dig("payload", "request_kind")
    assert_equal control_request.public_id,
      item.dig("payload", "conversation_control", "conversation_control_request_id")
    assert_equal context[:conversation].public_id, item.dig("payload", "conversation_control", "conversation_id")
    assert_equal context[:agent_program].public_id, item.dig("payload", "runtime_context", "agent_program_id")
    assert_equal context[:user].public_id, item.dig("payload", "runtime_context", "user_id")
    refute_includes response.body, %("#{control_request.id}")
  end

  test "poll does not deliver executor-plane close requests from the writer path" do
    context = build_rotated_runtime_context!
    process_run = create_process_run!(
      workflow_node: context[:workflow_node],
      executor_program: context[:executor_program],
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
      headers: agent_api_headers(context[:replacement_machine_credential]),
      as: :json

    assert_response :success

    response_body = JSON.parse(response.body)
    assert_empty response_body.fetch("mailbox_items")
    assert_equal context[:executor_program].id, mailbox_item.reload.target_executor_program_id
    assert_nil mailbox_item.leased_to_agent_session
    assert_nil mailbox_item.leased_to_executor_session
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
      scenario_builder.agent_program_request!(
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
        headers: agent_api_headers(context[:machine_credential]),
        as: :json
    end

    assert_response :success
    assert_operator queries.length, :<=, 41, "Expected program control poll to stay under 41 SQL queries, got #{queries.length}:\n#{queries.join("\n")}"
  end
end
