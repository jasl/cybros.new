#!/usr/bin/env ruby

require_relative "./phase2_acceptance_support"

runtime_base_url = ENV.fetch("FENIX_RUNTIME_BASE_URL", "http://127.0.0.1:3101")

Phase2AcceptanceSupport.reset_backend_state!
bootstrap = Phase2AcceptanceSupport.bootstrap_and_seed!

v1 = Phase2AcceptanceSupport.register_bundled_runtime_from_manifest!(
  installation: bootstrap.installation,
  runtime_base_url: runtime_base_url,
  environment_fingerprint: "phase2-bundled-rotation-environment",
  fingerprint: "phase2-bundled-fenix-v1",
  sdk_version: "fenix-0.1.0"
).fetch(:runtime)

conversation_context = Phase2AcceptanceSupport.create_conversation!(deployment: v1.deployment)
baseline = Phase2AcceptanceSupport.execute_provider_turn_on_conversation!(
  conversation: conversation_context.fetch(:conversation),
  deployment: v1.deployment,
  content: "Bundled rotation baseline turn"
)

v2 = Phase2AcceptanceSupport.register_bundled_runtime_from_manifest!(
  installation: bootstrap.installation,
  runtime_base_url: runtime_base_url,
  environment_fingerprint: "phase2-bundled-rotation-environment",
  fingerprint: "phase2-bundled-fenix-v2",
  sdk_version: "fenix-0.2.0"
).fetch(:runtime)

upgrade_previous_state = v1.deployment.reload.bootstrap_state
upgrade_new_state = v2.deployment.reload.bootstrap_state
upgrade_switch = Conversations::SwitchAgentDeployment.call(
  conversation: conversation_context.fetch(:conversation).reload,
  agent_deployment: v2.deployment
)
upgrade = Phase2AcceptanceSupport.execute_provider_turn_on_conversation!(
  conversation: conversation_context.fetch(:conversation).reload,
  deployment: v2.deployment,
  content: "Bundled rotation upgrade turn"
)

v0 = Phase2AcceptanceSupport.register_bundled_runtime_from_manifest!(
  installation: bootstrap.installation,
  runtime_base_url: runtime_base_url,
  environment_fingerprint: "phase2-bundled-rotation-environment",
  fingerprint: "phase2-bundled-fenix-v0-9",
  sdk_version: "fenix-0.0.9"
).fetch(:runtime)

downgrade_previous_state = v2.deployment.reload.bootstrap_state
downgrade_new_state = v0.deployment.reload.bootstrap_state
downgrade_switch = Conversations::SwitchAgentDeployment.call(
  conversation: conversation_context.fetch(:conversation).reload,
  agent_deployment: v0.deployment
)
downgrade = Phase2AcceptanceSupport.execute_provider_turn_on_conversation!(
  conversation: conversation_context.fetch(:conversation).reload,
  deployment: v0.deployment,
  content: "Bundled rotation downgrade turn"
)

Phase2AcceptanceSupport.write_json(
  {
    "conversation_id" => conversation_context.fetch(:conversation).public_id,
    "execution_environment_id" => v1.execution_environment.public_id,
    "baseline" => {
      "deployment_id" => v1.deployment.public_id,
      "turn_id" => baseline.fetch(:turn).public_id,
      "workflow_run_id" => baseline.fetch(:workflow_run).public_id,
      "selected_output_message_id" => baseline.fetch(:turn).selected_output_message.public_id,
      "selected_output_content" => baseline.fetch(:turn).selected_output_message.content,
      "observed_dag_shape" => Phase2AcceptanceSupport.workflow_node_keys(baseline.fetch(:workflow_run)),
      "observed_conversation_state" => Phase2AcceptanceSupport.workflow_state_hash(
        conversation: conversation_context.fetch(:conversation),
        workflow_run: baseline.fetch(:workflow_run),
        turn: baseline.fetch(:turn)
      ),
    },
    "expected_dag_shape" => ["turn_step"],
    "expected_conversation_state" => {
      "conversation_state" => "active",
      "workflow_lifecycle_state" => "completed",
      "workflow_wait_state" => "ready",
      "turn_lifecycle_state" => "completed",
    },
    "upgrade" => {
      "previous_deployment_id" => v1.deployment.public_id,
      "new_deployment_id" => v2.deployment.public_id,
      "previous_fingerprint" => v1.deployment.fingerprint,
      "new_fingerprint" => v2.deployment.fingerprint,
      "previous_sdk_version" => "fenix-0.1.0",
      "new_sdk_version" => "fenix-0.2.0",
      "previous_bootstrap_state_after_cutover" => upgrade_previous_state,
      "new_bootstrap_state_after_cutover" => upgrade_new_state,
      "conversation_agent_deployment_id_after_switch" => upgrade_switch.runtime_contract.fetch("agent_deployment_id"),
      "turn_id" => upgrade.fetch(:turn).public_id,
      "workflow_run_id" => upgrade.fetch(:workflow_run).public_id,
      "selected_output_message_id" => upgrade.fetch(:turn).selected_output_message.public_id,
      "selected_output_content" => upgrade.fetch(:turn).selected_output_message.content,
      "observed_dag_shape" => Phase2AcceptanceSupport.workflow_node_keys(upgrade.fetch(:workflow_run)),
      "observed_conversation_state" => Phase2AcceptanceSupport.workflow_state_hash(
        conversation: conversation_context.fetch(:conversation),
        workflow_run: upgrade.fetch(:workflow_run),
        turn: upgrade.fetch(:turn)
      ),
    },
    "downgrade" => {
      "previous_deployment_id" => v2.deployment.public_id,
      "new_deployment_id" => v0.deployment.public_id,
      "previous_fingerprint" => v2.deployment.fingerprint,
      "new_fingerprint" => v0.deployment.fingerprint,
      "previous_sdk_version" => "fenix-0.2.0",
      "new_sdk_version" => "fenix-0.0.9",
      "previous_bootstrap_state_after_cutover" => downgrade_previous_state,
      "new_bootstrap_state_after_cutover" => downgrade_new_state,
      "conversation_agent_deployment_id_after_switch" => downgrade_switch.runtime_contract.fetch("agent_deployment_id"),
      "turn_id" => downgrade.fetch(:turn).public_id,
      "workflow_run_id" => downgrade.fetch(:workflow_run).public_id,
      "selected_output_message_id" => downgrade.fetch(:turn).selected_output_message.public_id,
      "selected_output_content" => downgrade.fetch(:turn).selected_output_message.content,
      "observed_dag_shape" => Phase2AcceptanceSupport.workflow_node_keys(downgrade.fetch(:workflow_run)),
      "observed_conversation_state" => Phase2AcceptanceSupport.workflow_state_hash(
        conversation: conversation_context.fetch(:conversation),
        workflow_run: downgrade.fetch(:workflow_run),
        turn: downgrade.fetch(:turn)
      ),
    },
    "current_conversation_agent_deployment_id" => conversation_context.fetch(:conversation).reload.agent_deployment.public_id,
    "current_conversation_agent_deployment_fingerprint" => conversation_context.fetch(:conversation).agent_deployment.fingerprint,
  }
)
