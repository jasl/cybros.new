#!/usr/bin/env ruby

require_relative "../manual_acceptance_support"

runtime_base_url = ENV.fetch("FENIX_RUNTIME_BASE_URL", "http://127.0.0.1:3101")
delivery_mode = ENV.fetch("FENIX_DELIVERY_MODE", "realtime")
fingerprint = "phase2-bundled-fast-terminal-runtime"

ManualAcceptanceSupport.reset_backend_state!
bootstrap = ManualAcceptanceSupport.bootstrap_and_seed!
bundled = ManualAcceptanceSupport.register_bundled_runtime_from_manifest!(
  installation: bootstrap.installation,
  runtime_base_url: runtime_base_url,
  environment_fingerprint: "phase2-bundled-fast-terminal-environment",
  fingerprint: fingerprint,
  sdk_version: "fenix-0.1.0"
)

run = ManualAcceptanceSupport.run_fenix_mailbox_task!(
  deployment: bundled.fetch(:runtime).deployment,
  machine_credential: bundled.fetch(:machine_credential),
  runtime_base_url: runtime_base_url,
  content: "Bundled Fenix deterministic tool turn",
  mode: "deterministic_tool",
  extra_payload: { "expression" => "7 + 5" },
  delivery_mode: delivery_mode
)

ManualAcceptanceSupport.write_json(
  {
    "deployment_id" => bundled.fetch(:runtime).deployment.public_id,
    "delivery_mode" => delivery_mode,
    "execution_environment_id" => bundled.fetch(:runtime).execution_environment.public_id,
    "conversation_id" => run.fetch(:conversation).public_id,
    "turn_id" => run.fetch(:turn).public_id,
    "workflow_run_id" => run.fetch(:workflow_run).public_id,
    "agent_task_run_id" => run.fetch(:agent_task_run).public_id,
    "expected_dag_shape" => ["agent_turn_step"],
    "observed_dag_shape" => ManualAcceptanceSupport.workflow_node_keys(run.fetch(:workflow_run)),
    "expected_conversation_state" => {
      "conversation_state" => "active",
      "workflow_lifecycle_state" => "completed",
      "workflow_wait_state" => "ready",
      "turn_lifecycle_state" => "active",
      "agent_task_run_state" => "completed",
    },
    "observed_conversation_state" => ManualAcceptanceSupport.workflow_state_hash(
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
