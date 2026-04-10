#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../lib/boot'

runtime_base_url = ENV.fetch('FENIX_RUNTIME_BASE_URL', 'http://127.0.0.1:3101')
delivery_mode = ENV.fetch('FENIX_DELIVERY_MODE', 'realtime')
fingerprint = 'acceptance-bundled-fast-terminal-runtime'

Acceptance::ManualSupport.reset_backend_state!
bootstrap = Acceptance::ManualSupport.bootstrap_and_seed!
bundled = Acceptance::ManualSupport.register_bundled_runtime_from_manifest!(
  installation: bootstrap.installation,
  runtime_base_url: runtime_base_url,
  executor_fingerprint: 'acceptance-bundled-fast-terminal-environment',
  fingerprint: fingerprint
)

run = Acceptance::ManualSupport.run_fenix_mailbox_task!(
  deployment: bundled.deployment,
  machine_credential: bundled.machine_credential,
  executor_machine_credential: bundled.executor_machine_credential,
  runtime_base_url: runtime_base_url,
  content: 'Bundled Fenix deterministic tool turn',
  mode: 'deterministic_tool',
  extra_payload: { 'expression' => '7 + 5' },
  delivery_mode: delivery_mode
)

expected_dag_shape = ['agent_turn_step']
observed_dag_shape = Acceptance::ManualSupport.workflow_node_keys(run.fetch(:workflow_run))
expected_conversation_state = {
  'conversation_state' => 'active',
  'workflow_lifecycle_state' => 'completed',
  'workflow_wait_state' => 'ready',
  'turn_lifecycle_state' => 'active',
  'agent_task_run_state' => 'completed'
}
observed_conversation_state = Acceptance::ManualSupport.workflow_state_hash(
  conversation: run.fetch(:conversation),
  workflow_run: run.fetch(:workflow_run),
  turn: run.fetch(:turn),
  agent_task_run: run.fetch(:agent_task_run)
)

Acceptance::ManualSupport.write_json(
  Acceptance::ManualSupport.scenario_result(
    scenario: 'bundled_fast_terminal_validation',
    expected_dag_shape: expected_dag_shape,
    observed_dag_shape: observed_dag_shape,
    expected_conversation_state: expected_conversation_state,
    observed_conversation_state: observed_conversation_state,
    extra: {
      'deployment_id' => bundled.deployment.public_id,
      'delivery_mode' => delivery_mode,
      'executor_program_id' => bundled.executor_program.public_id,
      'conversation_id' => run.fetch(:conversation).public_id,
      'turn_id' => run.fetch(:turn).public_id,
      'workflow_run_id' => run.fetch(:workflow_run).public_id,
      'agent_task_run_id' => run.fetch(:agent_task_run).public_id,
      'runtime_execution_status' => run.fetch(:execution).fetch('status'),
      'runtime_output' => run.fetch(:execution)['output'],
      'report_results' => run.fetch(:report_results)
    }
  )
)
