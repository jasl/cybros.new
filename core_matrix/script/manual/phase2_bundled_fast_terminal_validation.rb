#!/usr/bin/env ruby

require_relative "./phase2_acceptance_support"

runtime_base_url = ENV.fetch("FENIX_RUNTIME_BASE_URL", "http://127.0.0.1:3101")
fingerprint = "phase2-bundled-fast-terminal-runtime"

Phase2AcceptanceSupport.reset_backend_state!
bootstrap = Phase2AcceptanceSupport.bootstrap_and_seed!
bundled = Phase2AcceptanceSupport.register_bundled_runtime_from_manifest!(
  installation: bootstrap.installation,
  runtime_base_url: runtime_base_url,
  environment_fingerprint: "phase2-bundled-fast-terminal-environment",
  fingerprint: fingerprint,
  sdk_version: "fenix-0.1.0"
)

run = Phase2AcceptanceSupport.run_fenix_mailbox_task!(
  deployment: bundled.fetch(:runtime).deployment,
  machine_credential: bundled.fetch(:machine_credential),
  runtime_base_url: runtime_base_url,
  content: "Bundled Fenix deterministic tool turn",
  mode: "deterministic_tool",
  extra_payload: { "expression" => "7 + 5" }
)

Phase2AcceptanceSupport.write_json(
  {
    "deployment_id" => bundled.fetch(:runtime).deployment.public_id,
    "execution_environment_id" => bundled.fetch(:runtime).execution_environment.public_id,
    "conversation_id" => run.fetch(:conversation).public_id,
    "turn_id" => run.fetch(:turn).public_id,
    "workflow_run_id" => run.fetch(:workflow_run).public_id,
    "agent_task_run_id" => run.fetch(:agent_task_run).public_id,
    "expected_dag_shape" => ["agent_turn_step"],
    "observed_dag_shape" => Phase2AcceptanceSupport.workflow_node_keys(run.fetch(:workflow_run)),
    "expected_conversation_state" => {
      "conversation_state" => "active",
      "workflow_lifecycle_state" => "active",
      "workflow_wait_state" => "ready",
      "turn_lifecycle_state" => "active",
      "agent_task_run_state" => "completed",
    },
    "observed_conversation_state" => Phase2AcceptanceSupport.workflow_state_hash(
      conversation: run.fetch(:conversation),
      workflow_run: run.fetch(:workflow_run),
      turn: run.fetch(:turn),
      agent_task_run: run.fetch(:agent_task_run)
    ),
    "runtime_execution_status" => run.fetch(:execution).fetch("status"),
    "runtime_output" => run.fetch(:execution)["output"],
    "report_results" => run.fetch(:report_results),
  }
)
