#!/usr/bin/env ruby
# ACCEPTANCE_MODE: internal_workflow
# This scenario intentionally exercises internal governed-tool task semantics because there is no equivalent app_api surface.

ENV["RAILS_ENV"] ||= "development"

require_relative "../lib/boot"
require "json"
require_relative "../lib/governed_validation_support"

runtime_context = GovernedValidationSupport.bootstrap_runtime!(
  agent_key: "acceptance-governed-tool",
  display_name: "Acceptance Governed Tool Runtime",
  execution_runtime_fingerprint: "acceptance-governed-tool-environment",
  fingerprint: "acceptance-governed-tool-runtime",
  tool_contract: [],
  profile_policy: {
    "main" => {
      "label" => "Main",
      "description" => "Primary interactive profile",
      "allowed_tool_names" => ["subagent_spawn"],
    },
  },
  default_canonical_config: {
    "sandbox" => "workspace-write",
    "interactive" => {
      "selector" => "role:main",
      "profile" => "main",
    },
    "subagents" => {
      "enabled" => true,
      "allow_nested" => true,
      "max_depth" => 3,
    },
  }
)

task_context = GovernedValidationSupport.create_task_context!(
  workspace: runtime_context.fetch(:workspace),
  agent_definition_version: runtime_context.fetch(:runtime).agent_definition_version,
  content: "Spawn one governed subagent and report the durable records.",
  allowed_tool_names: ["subagent_spawn"]
)

task_run = task_context.fetch(:agent_task_run)
binding = task_run.tool_bindings.joins(:tool_definition).find_by!(
  tool_definition: { tool_name: "subagent_spawn" }
)

invocation = ToolInvocations::Start.call(
  tool_binding: binding,
  request_payload: {
    "content" => "Investigate the delegated task.",
    "scope" => "turn",
    "task_payload" => { "source" => "acceptance_governed_tool_validation" },
  }
)

spawn_result = SubagentConnections::Spawn.call(
  conversation: task_context.fetch(:conversation),
  origin_turn: task_context.fetch(:turn),
  content: "Investigate the delegated task.",
  scope: "turn",
  task_payload: { "source" => "acceptance_governed_tool_validation" }
)

completed = ToolInvocations::Complete.call(
  tool_invocation: invocation,
  response_payload: spawn_result
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
    scenario: "governed_tool_validation",
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
      "tool_invocation_id" => completed.public_id,
      "governance_mode" => binding.tool_definition.governance_mode,
      "tool_invocation_status" => completed.status,
      "request_payload" => completed.request_payload,
      "response_payload" => completed.response_payload,
    }
  )
)
