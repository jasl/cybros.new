#!/usr/bin/env ruby

ENV["RAILS_ENV"] ||= "development"

require_relative "../../config/environment"
require "json"
require_relative "./phase2_governed_validation_support"

runtime_context = Phase2GovernedValidationSupport.bootstrap_runtime!(
  agent_key: "phase2-governed-tool",
  display_name: "Phase 2 Governed Tool Runtime",
  environment_fingerprint: "phase2-governed-tool-environment",
  fingerprint: "phase2-governed-tool-runtime",
  tool_catalog: [],
  profile_catalog: {
    "main" => {
      "label" => "Main",
      "description" => "Primary interactive profile",
      "allowed_tool_names" => ["subagent_spawn"],
    },
  },
  default_config_snapshot: {
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

task_context = Phase2GovernedValidationSupport.create_task_context!(
  workspace: runtime_context.fetch(:workspace),
  deployment: runtime_context.fetch(:runtime).deployment,
  capability_snapshot: runtime_context.fetch(:runtime).capability_snapshot,
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
    "task_payload" => { "source" => "phase2_governed_tool_validation" },
  }
)

spawn_result = SubagentSessions::Spawn.call(
  conversation: task_context.fetch(:conversation),
  origin_turn: task_context.fetch(:turn),
  content: "Investigate the delegated task.",
  scope: "turn",
  task_payload: { "source" => "phase2_governed_tool_validation" }
)

completed = ToolInvocations::Complete.call(
  tool_invocation: invocation,
  response_payload: spawn_result
)

puts JSON.pretty_generate(
  {
    "conversation_id" => task_context.fetch(:conversation).public_id,
    "turn_id" => task_context.fetch(:turn).public_id,
    "workflow_run_id" => task_context.fetch(:workflow_run).public_id,
    "agent_task_run_id" => task_run.public_id,
    "tool_binding_id" => binding.public_id,
    "tool_definition_id" => binding.tool_definition.public_id,
    "tool_implementation_id" => binding.tool_implementation.public_id,
    "tool_invocation_id" => completed.public_id,
    "governance_mode" => binding.tool_definition.governance_mode,
    "expected_dag_shape" => ["root->agent_turn_step"],
    "observed_dag_shape" => Phase2GovernedValidationSupport.dag_edges(task_context.fetch(:workflow_run)),
    "expected_conversation_state" => {
      "conversation_state" => "active",
      "workflow_lifecycle_state" => "completed",
      "workflow_wait_state" => "ready",
      "turn_lifecycle_state" => "active",
    },
    "observed_conversation_state" => Phase2GovernedValidationSupport.conversation_state(
      conversation: task_context.fetch(:conversation),
      workflow_run: task_context.fetch(:workflow_run)
    ),
    "tool_invocation_status" => completed.status,
    "request_payload" => completed.request_payload,
    "response_payload" => completed.response_payload,
  }
)
