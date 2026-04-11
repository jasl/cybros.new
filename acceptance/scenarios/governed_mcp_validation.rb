#!/usr/bin/env ruby

ENV["RAILS_ENV"] ||= "development"

require_relative "../lib/boot"
require "json"
require_relative "../../core_matrix/test/support/fake_streamable_http_mcp_server"
require_relative "../lib/governed_validation_support"

server = FakeStreamableHttpMcpServer.new.start

begin
  runtime_context = GovernedValidationSupport.bootstrap_runtime!(
    agent_key: "acceptance-governed-mcp",
    display_name: "Acceptance Governed MCP Runtime",
    execution_runtime_fingerprint: "acceptance-governed-mcp-environment",
    fingerprint: "acceptance-governed-mcp-runtime",
    tool_catalog: [
      {
        "tool_name" => "remote_echo",
        "tool_kind" => "agent_observation",
        "implementation_source" => "mcp",
        "implementation_ref" => "mcp/echo",
        "transport_kind" => "streamable_http",
        "server_url" => server.base_url,
        "mcp_tool_name" => "echo",
        "input_schema" => {
          "type" => "object",
          "properties" => {
            "message" => { "type" => "string" },
          },
        },
        "result_schema" => { "type" => "object", "properties" => {} },
        "streaming_support" => false,
        "idempotency_policy" => "best_effort",
      },
    ],
    profile_catalog: {
      "main" => {
        "label" => "Main",
        "description" => "Primary interactive profile",
        "allowed_tool_names" => ["remote_echo"],
      },
    },
    default_config_snapshot: {
      "sandbox" => "workspace-write",
      "interactive" => {
        "selector" => "role:main",
        "profile" => "main",
      },
    }
  )

  task_context = GovernedValidationSupport.create_task_context!(
    workspace: runtime_context.fetch(:workspace),
    agent_snapshot: runtime_context.fetch(:runtime).agent_snapshot,
    capability_snapshot: runtime_context.fetch(:runtime).capability_snapshot,
    content: "Call the governed Streamable HTTP MCP echo tool.",
    allowed_tool_names: ["remote_echo"]
  )

  task_run = task_context.fetch(:agent_task_run)
  binding = task_run.tool_bindings.joins(:tool_definition).find_by!(
    tool_definition: { tool_name: "remote_echo" }
  )

  first = MCP::InvokeTool.call(
    tool_binding: binding,
    request_payload: { "arguments" => { "message" => "first" } }
  )

  server.fail_next_tool_call_with_session_not_found!

  second = MCP::InvokeTool.call(
    tool_binding: binding.reload,
    request_payload: { "arguments" => { "message" => "second" } }
  )

  third = MCP::InvokeTool.call(
    tool_binding: binding.reload,
    request_payload: { "arguments" => { "message" => "third" } }
  )

  expected_dag_shape = ["root->agent_turn_step"]
  observed_dag_shape = GovernedValidationSupport.dag_edges(task_context.fetch(:workflow_run))
  expected_conversation_state = {
    "conversation_state" => "active",
    "workflow_lifecycle_state" => "active",
    "workflow_wait_state" => "ready",
    "turn_lifecycle_state" => "active",
  }
  observed_conversation_state = GovernedValidationSupport.conversation_state(
    conversation: task_context.fetch(:conversation),
    workflow_run: task_context.fetch(:workflow_run)
  )

  Acceptance::ManualSupport.write_json(
    Acceptance::ManualSupport.scenario_result(
      scenario: "governed_mcp_validation",
      expected_dag_shape: expected_dag_shape,
      observed_dag_shape: observed_dag_shape,
      expected_conversation_state: expected_conversation_state,
      observed_conversation_state: observed_conversation_state,
      extra: {
        "conversation_id" => task_context.fetch(:conversation).public_id,
        "turn_id" => task_context.fetch(:turn).public_id,
        "workflow_run_id" => task_context.fetch(:workflow_run).public_id,
        "agent_task_run_id" => task_run.public_id,
        "tool_binding_id" => binding.public_id,
        "tool_definition_id" => binding.tool_definition.public_id,
        "tool_implementation_id" => binding.tool_implementation.public_id,
        "tool_invocation_ids" => [first.public_id, second.public_id, third.public_id],
        "tool_invocation_statuses" => task_run.reload.tool_invocations.order(:attempt_no).pluck(:status),
        "failure_classification" => second.error_payload.fetch("classification"),
        "failure_code" => second.error_payload.fetch("code"),
        "binding_payload" => binding.reload.binding_payload,
        "issued_session_ids" => server.issued_session_ids,
        "final_response_payload" => third.response_payload,
      }
    )
  )
ensure
  server&.shutdown
end
