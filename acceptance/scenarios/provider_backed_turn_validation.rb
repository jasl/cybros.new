#!/usr/bin/env ruby

require_relative "../lib/boot"

runtime_base_url = ENV.fetch("FENIX_RUNTIME_BASE_URL", "http://127.0.0.1:3101")
fingerprint = "acceptance-provider-backed-runtime"
selector = ENV.fetch("PHASE2_PROVIDER_SELECTOR", "candidate:openrouter/openai-gpt-5.4")
content = ENV.fetch(
  "PHASE2_PROVIDER_PROMPT",
  "Reply with ACCEPTED-PHASE2 exactly. Do not add any other words or punctuation."
)

ManualAcceptanceSupport.reset_backend_state!
bootstrap = ManualAcceptanceSupport.bootstrap_and_seed!
bundled = ManualAcceptanceSupport.register_bundled_runtime_from_manifest!(
  installation: bootstrap.installation,
  runtime_base_url: runtime_base_url,
  runtime_fingerprint: "acceptance-provider-backed-environment",
  fingerprint: fingerprint,
  sdk_version: "fenix-0.1.0"
)
conversation_context = ManualAcceptanceSupport.create_conversation!(deployment: bundled.fetch(:runtime).deployment)
run = ManualAcceptanceSupport.start_turn_workflow_on_conversation!(
  conversation: conversation_context.fetch(:conversation),
  deployment: bundled.fetch(:runtime).deployment,
  content: content,
  root_node_key: "turn_step",
  root_node_type: "turn_step",
  decision_source: "system",
  selector_source: "manual",
  selector: selector
)
ManualAcceptanceSupport.execute_provider_workflow!(workflow_run: run.fetch(:workflow_run))

workflow_run = run.fetch(:workflow_run).reload
turn = run.fetch(:turn).reload
model_context = workflow_run.execution_snapshot.model_context

expected_dag_shape = ["turn_step"]
observed_dag_shape = ManualAcceptanceSupport.workflow_node_keys(workflow_run)
expected_conversation_state = {
  "conversation_state" => "active",
  "workflow_lifecycle_state" => "completed",
  "workflow_wait_state" => "ready",
  "turn_lifecycle_state" => "completed",
}
observed_conversation_state = ManualAcceptanceSupport.workflow_state_hash(
  conversation: conversation_context.fetch(:conversation),
  workflow_run: workflow_run,
  turn: turn,
  extra: {
    "selected_output_message_id" => turn.selected_output_message&.public_id,
    "selected_output_content" => turn.selected_output_message&.content,
  }
)

ManualAcceptanceSupport.write_json(
  ManualAcceptanceSupport.scenario_result(
    scenario: "provider_backed_turn_validation",
    expected_dag_shape: expected_dag_shape,
    observed_dag_shape: observed_dag_shape,
    expected_conversation_state: expected_conversation_state,
    observed_conversation_state: observed_conversation_state,
    extra: {
      "deployment_id" => bundled.fetch(:runtime).deployment.public_id,
      "execution_runtime_id" => bundled.fetch(:runtime).execution_runtime.public_id,
      "conversation_id" => conversation_context.fetch(:conversation).public_id,
      "turn_id" => turn.public_id,
      "workflow_run_id" => workflow_run.public_id,
      "provider_handle" => model_context["provider_handle"],
      "model_ref" => model_context["model_ref"],
      "api_model" => model_context["api_model"],
      "selector" => workflow_run.normalized_selector,
    }
  )
)
