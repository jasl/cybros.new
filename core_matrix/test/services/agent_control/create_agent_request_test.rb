require "test_helper"

class AgentControl::CreateAgentRequestTest < ActiveSupport::TestCase
  test "creates and publishes an agent-definition-version-targeted mailbox request for the agent" do
    context = build_agent_control_context!
    published = []
    original_publish_pending = AgentControl::PublishPending.method(:call)

    AgentControl::PublishPending.singleton_class.define_method(:call) do |mailbox_item:|
      published << mailbox_item
      mailbox_item
    end

    mailbox_item = AgentControl::CreateAgentRequest.call(
      agent_definition_version: context.fetch(:agent_definition_version),
      request_kind: "prepare_round",
      payload: {
        "task" => {
          "kind" => "turn_step",
          "workflow_node_id" => context.fetch(:workflow_node).public_id,
          "workflow_run_id" => context.fetch(:workflow_run).public_id,
          "turn_id" => context.fetch(:turn).public_id,
          "conversation_id" => context.fetch(:conversation).public_id,
        },
      },
      logical_work_id: "prepare-round:#{context.fetch(:workflow_node).public_id}",
      attempt_no: 2,
      dispatch_deadline_at: 5.minutes.from_now
    )

    assert_equal "agent_request", mailbox_item.item_type
    assert_equal "agent", mailbox_item.control_plane
    refute_respond_to mailbox_item, :target_kind
    assert_equal context.fetch(:agent_definition_version), mailbox_item.target_agent_definition_version
    assert_equal context.fetch(:agent), mailbox_item.target_agent
    assert_equal "prepare_round", mailbox_item.payload.fetch("request_kind")
    assert_equal({ "request_kind" => "prepare_round" }, mailbox_item.payload_body)
    assert_equal "agent_request", mailbox_item.payload_document.document_kind
    assert_equal 2, mailbox_item.attempt_no
    assert_equal [mailbox_item], published
  ensure
    AgentControl::PublishPending.singleton_class.define_method(:call, original_publish_pending) if original_publish_pending
  end

  test "prepare_round rejects missing workflow task context" do
    context = build_agent_control_context!

    error = assert_raises(ArgumentError) do
      AgentControl::CreateAgentRequest.call(
        agent_definition_version: context.fetch(:agent_definition_version),
        request_kind: "prepare_round",
        payload: {
          "conversation_id" => context.fetch(:conversation).public_id,
        },
        logical_work_id: "prepare-round:missing-task",
        attempt_no: 1,
        dispatch_deadline_at: 5.minutes.from_now
      )
    end

    assert_match(/missing task payload/i, error.message)
  end

  test "stores only the request body in the payload document and reconstructs structured runtime context on read" do
    context = build_agent_control_context!
    logical_work_id = "prepare-round:#{context.fetch(:workflow_node).public_id}"

    mailbox_item = AgentControl::CreateAgentRequest.call(
      agent_definition_version: context.fetch(:agent_definition_version),
      request_kind: "prepare_round",
      payload: {
        "task" => {
          "kind" => "turn_step",
          "workflow_node_id" => context.fetch(:workflow_node).public_id,
          "workflow_run_id" => context.fetch(:workflow_run).public_id,
          "turn_id" => context.fetch(:turn).public_id,
          "conversation_id" => context.fetch(:conversation).public_id,
        },
        "provider_context" => context.fetch(:turn).execution_contract.provider_context,
        "runtime_context" => {
          "logical_work_id" => logical_work_id,
          "attempt_no" => 3,
          "control_plane" => "agent",
          "agent_definition_version_id" => context.fetch(:agent_definition_version).public_id,
          "agent_id" => context.fetch(:agent).public_id,
          "user_id" => context.fetch(:user).public_id,
          "custom_flag" => "keep-me",
        },
      },
      logical_work_id: logical_work_id,
      attempt_no: 3,
      dispatch_deadline_at: 5.minutes.from_now
    )

    stored_payload = mailbox_item.payload_document.payload

    refute stored_payload.key?("request_kind")
    refute stored_payload.key?("provider_context")
    refute stored_payload.key?("task")
    assert_equal(
      {
        "agent_id" => context.fetch(:agent).public_id,
        "user_id" => context.fetch(:user).public_id,
        "custom_flag" => "keep-me",
      },
      stored_payload.fetch("runtime_context")
    )
    assert_equal context.fetch(:workflow_node), mailbox_item.workflow_node
    assert_equal context.fetch(:turn).execution_contract, mailbox_item.execution_contract
    assert_equal "prepare_round", mailbox_item.payload.fetch("request_kind")
    assert_equal context.fetch(:conversation).public_id, mailbox_item.payload.dig("task", "conversation_id")
    assert_equal context.fetch(:turn).public_id, mailbox_item.payload.dig("task", "turn_id")
    assert_equal context.fetch(:workflow_run).public_id, mailbox_item.payload.dig("task", "workflow_run_id")
    assert_equal context.fetch(:workflow_node).public_id, mailbox_item.payload.dig("task", "workflow_node_id")
    assert_equal context.fetch(:turn).execution_contract.provider_context, mailbox_item.payload.fetch("provider_context")
    assert_equal logical_work_id, mailbox_item.payload.dig("runtime_context", "logical_work_id")
    assert_equal 3, mailbox_item.payload.dig("runtime_context", "attempt_no")
    assert_equal "agent", mailbox_item.payload.dig("runtime_context", "control_plane")
    assert_equal context.fetch(:agent_definition_version).public_id, mailbox_item.payload.dig("runtime_context", "agent_definition_version_id")
    assert_equal context.fetch(:agent).public_id, mailbox_item.payload.dig("runtime_context", "agent_id")
    assert_equal context.fetch(:user).public_id, mailbox_item.payload.dig("runtime_context", "user_id")
    assert_equal "keep-me", mailbox_item.payload.dig("runtime_context", "custom_flag")
  end

  test "reconstructs prepare_round snapshot context from the execution contract instead of storing it inline" do
    context = build_agent_control_context!
    execution_snapshot = context.fetch(:turn).execution_snapshot
    logical_work_id = "prepare-round:#{context.fetch(:workflow_node).public_id}"
    round_context = execution_snapshot.conversation_projection.slice("messages", "context_imports", "projection_fingerprint")
    capability_projection = execution_snapshot.capability_projection
    expected_agent_context = {
      "profile" => capability_projection.fetch("profile_key", "main"),
      "is_subagent" => capability_projection["is_subagent"] == true,
      "subagent_connection_id" => capability_projection["subagent_connection_id"],
      "parent_subagent_connection_id" => capability_projection["parent_subagent_connection_id"],
      "subagent_depth" => capability_projection["subagent_depth"],
      "owner_conversation_id" => capability_projection["owner_conversation_id"],
      "allowed_tool_names" => capability_projection.fetch("tool_surface", []).map { |entry| entry.fetch("tool_name") }.uniq,
    }.compact

    mailbox_item = AgentControl::CreateAgentRequest.call(
      agent_definition_version: context.fetch(:agent_definition_version),
      request_kind: "prepare_round",
      payload: {
        "protocol_version" => "agent-runtime/2026-04-01",
        "task" => {
          "kind" => "turn_step",
          "workflow_node_id" => context.fetch(:workflow_node).public_id,
          "workflow_run_id" => context.fetch(:workflow_run).public_id,
          "turn_id" => context.fetch(:turn).public_id,
          "conversation_id" => context.fetch(:conversation).public_id,
        },
        "round_context" => round_context,
        "agent_context" => expected_agent_context,
        "provider_context" => execution_snapshot.provider_context,
        "runtime_context" => {
          "logical_work_id" => logical_work_id,
          "attempt_no" => 1,
          "control_plane" => "agent",
          "agent_definition_version_id" => context.fetch(:agent_definition_version).public_id,
        },
      },
      logical_work_id: logical_work_id,
      attempt_no: 1,
      dispatch_deadline_at: 5.minutes.from_now
    )

    stored_payload = mailbox_item.payload_document.payload

    refute stored_payload.key?("protocol_version")
    refute stored_payload.key?("round_context")
    refute stored_payload.key?("agent_context")
    refute stored_payload.key?("provider_context")

    assert_equal "agent-runtime/2026-04-01", mailbox_item.payload.fetch("protocol_version")
    assert_equal round_context, mailbox_item.payload.fetch("round_context")
    assert_equal expected_agent_context, mailbox_item.payload.fetch("agent_context")
    assert_equal execution_snapshot.provider_context, mailbox_item.payload.fetch("provider_context")
  end

  test "supports supervision control request kinds without workflow context" do
    context = build_agent_control_context!

    mailbox_item = AgentControl::CreateAgentRequest.call(
      agent_definition_version: context.fetch(:agent_definition_version),
      request_kind: "supervision_status_refresh",
      payload: {
        "conversation_control" => {
          "conversation_control_request_id" => "control-request-public-id",
          "conversation_id" => context.fetch(:conversation).public_id,
        },
      },
      logical_work_id: "supervision-status-refresh:#{context.fetch(:conversation).public_id}",
      attempt_no: 1,
      dispatch_deadline_at: 5.minutes.from_now
    )

    assert_equal "supervision_status_refresh", mailbox_item.payload.fetch("request_kind")
    assert_equal "control-request-public-id",
      mailbox_item.payload.dig("conversation_control", "conversation_control_request_id")
    assert_nil mailbox_item.workflow_node
    assert_nil mailbox_item.execution_contract
  end

  test "supports execute_tool requests while preserving agent tool call payloads" do
    context = build_agent_control_context!

    mailbox_item = AgentControl::CreateAgentRequest.call(
      agent_definition_version: context.fetch(:agent_definition_version),
      request_kind: "execute_tool",
      payload: {
        "task" => {
          "kind" => "turn_step",
          "workflow_node_id" => context.fetch(:workflow_node).public_id,
          "workflow_run_id" => context.fetch(:workflow_run).public_id,
          "turn_id" => context.fetch(:turn).public_id,
          "conversation_id" => context.fetch(:conversation).public_id,
        },
        "tool_call" => {
          "call_id" => "call-1",
          "tool_name" => "exec_command",
          "arguments" => { "cmd" => "pwd", "timeout_seconds" => 15 },
        },
        "runtime_context" => {
          "agent_id" => context.fetch(:agent).public_id,
          "user_id" => context.fetch(:user).public_id,
        },
      },
      logical_work_id: "tool-call:#{context.fetch(:workflow_node).public_id}:call-1",
      attempt_no: 1,
      dispatch_deadline_at: 5.minutes.from_now
    )

    assert_equal "execute_tool", mailbox_item.payload.fetch("request_kind")
    assert_equal "call-1", mailbox_item.payload.dig("tool_call", "call_id")
    assert_equal "exec_command", mailbox_item.payload.dig("tool_call", "tool_name")
    assert_equal "pwd", mailbox_item.payload.dig("tool_call", "arguments", "cmd")
    assert_equal 15, mailbox_item.payload.dig("tool_call", "arguments", "timeout_seconds")
    assert_equal context.fetch(:workflow_node).public_id, mailbox_item.payload.dig("task", "workflow_node_id")
    assert_equal context.fetch(:agent).public_id, mailbox_item.payload.dig("runtime_context", "agent_id")
    assert_equal context.fetch(:user).public_id, mailbox_item.payload.dig("runtime_context", "user_id")
    assert_equal(
      {
        "tool_call" => {
          "call_id" => "call-1",
          "tool_name" => "exec_command",
          "arguments" => { "cmd" => "pwd", "timeout_seconds" => 15 },
        },
        "runtime_context" => {
          "agent_id" => context.fetch(:agent).public_id,
          "user_id" => context.fetch(:user).public_id,
        },
      },
      mailbox_item.payload_document.payload
    )
  end

  test "reconstructs consult_prompt_compaction payload from the execution contract while preserving prompt payload" do
    context = build_agent_control_context!
    execution_snapshot = context.fetch(:turn).execution_snapshot
    logical_work_id = "prompt-compaction-consult:#{context.fetch(:workflow_node).public_id}"

    mailbox_item = AgentControl::CreateAgentRequest.call(
      agent_definition_version: context.fetch(:agent_definition_version),
      request_kind: "consult_prompt_compaction",
      payload: {
        "protocol_version" => "agent-runtime/2026-04-01",
        "task" => {
          "kind" => "turn_step",
          "workflow_node_id" => context.fetch(:workflow_node).public_id,
          "workflow_run_id" => context.fetch(:workflow_run).public_id,
          "turn_id" => context.fetch(:turn).public_id,
          "conversation_id" => context.fetch(:conversation).public_id,
        },
        "agent_context" => {
          "profile" => "main",
          "allowed_tool_names" => %w[compact_context exec_command],
        },
        "provider_context" => execution_snapshot.provider_context,
        "runtime_context" => {
          "logical_work_id" => logical_work_id,
          "attempt_no" => 1,
          "control_plane" => "agent",
          "agent_definition_version_id" => context.fetch(:agent_definition_version).public_id,
        },
        "prompt_compaction" => {
          "consultation_reason" => "soft_threshold",
          "selected_input_message_id" => context.fetch(:turn).selected_input_message.public_id,
          "candidate_messages" => [
            { "role" => "system", "content" => "System prompt" },
            { "role" => "user", "content" => "Newest input" },
          ],
          "guard_result" => {
            "decision" => "consult",
            "estimated_tokens" => 128,
          },
        },
      },
      logical_work_id: logical_work_id,
      attempt_no: 1,
      dispatch_deadline_at: 5.minutes.from_now
    )

    stored_payload = mailbox_item.payload_document.payload

    refute stored_payload.key?("protocol_version")
    refute stored_payload.key?("agent_context")
    refute stored_payload.key?("provider_context")
    refute stored_payload.key?("task")
    assert_equal "soft_threshold", stored_payload.dig("prompt_compaction", "consultation_reason")
    assert_equal "agent-runtime/2026-04-01", mailbox_item.payload.fetch("protocol_version")
    assert_equal execution_snapshot.provider_context, mailbox_item.payload.fetch("provider_context")
    assert_equal "main", mailbox_item.payload.dig("agent_context", "profile")
    assert_equal(
      context.fetch(:workflow_node).public_id,
      mailbox_item.payload.dig("task", "workflow_node_id")
    )
    assert_equal(
      context.fetch(:turn).selected_input_message.public_id,
      mailbox_item.payload.dig("prompt_compaction", "selected_input_message_id")
    )
  end
end
