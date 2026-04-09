#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "pathname"
require "time"

require_relative "../lib/boot"
require_relative "../lib/perf/profile"
require_relative "../lib/perf/topology"
require_relative "../lib/perf/workload_manifest"
require_relative "../lib/perf/runtime_registration_matrix"
require_relative "../lib/perf/workload_driver"
require_relative "../lib/perf/workload_executor"
require_relative "../lib/perf/provider_catalog_override"
require_relative "../lib/perf/event_reader"
require_relative "../lib/perf/metrics_aggregator"
require_relative "../lib/perf/gate_evaluator"
require_relative "../lib/perf/report_builder"

def write_json(path, payload)
  FileUtils.mkdir_p(File.dirname(path))
  File.write(path, JSON.pretty_generate(payload) + "\n")
end

def write_text(path, contents)
  FileUtils.mkdir_p(File.dirname(path))
  File.binwrite(path, contents)
end

def append_jsonl(path, payload)
  FileUtils.mkdir_p(File.dirname(path))
  File.open(path, "a") { |file| file.puts(JSON.generate(payload)) }
end

def decorate_boot_states!(registration_matrix, topology)
  topology.runtime_slots.each do |slot|
    registration = registration_matrix.fetch("runtime_registrations").find { |entry| entry.fetch("slot_label") == slot.label }
    next unless registration

    next unless slot.runtime_boot_json_path.exist?

    payload = JSON.parse(slot.runtime_boot_json_path.read)
    registration["boot_status"] = payload.fetch("event", "ready") == "ready" ? "ready" : "failed"
    registration["boot_error"] = payload["error"] || payload["message"] unless registration["boot_status"] == "ready"
  rescue JSON::ParserError => error
    registration["boot_status"] = "failed"
    registration["boot_error"] = "invalid boot json: #{error.message}"
  end
end

def execute_mailbox_task_on_conversation!(conversation:, agent_program_version:, registration:, task:, slot_label:)
  run = ManualAcceptanceSupport.start_turn_workflow_on_conversation!(
    conversation: conversation,
    agent_program_version: agent_program_version,
    content: task.fetch("content"),
    root_node_key: "agent_turn_step",
    root_node_type: "turn_step",
    decision_source: "agent_program",
    initial_kind: "turn_step",
    initial_payload: { "mode" => task.fetch("mode") }.merge(task.fetch("extra_payload", {}))
  )
  agent_task_run = ManualAcceptanceSupport.wait_for_agent_task_terminal!(agent_task_run: run.fetch(:agent_task_run), timeout_seconds: 30)
  terminal_payload = agent_task_run.terminal_payload || {}
  execution = {
    "status" => agent_task_run.lifecycle_state == "completed" ? "completed" : "failed",
    "output" => terminal_payload["output"],
    "error" => agent_task_run.lifecycle_state == "completed" ? nil : terminal_payload,
  }

  {
    "status" => execution.fetch("status"),
    "conversation_public_id" => conversation.public_id,
    "turn_public_id" => run.fetch(:turn).public_id,
    "workflow_run_public_id" => run.fetch(:workflow_run).public_id,
    "agent_task_run_public_id" => agent_task_run.public_id,
    "runtime_output" => execution["output"],
    "runtime_error" => execution["error"],
  }
end

def execute_program_exchange_task_on_conversation!(conversation:, agent_program_version:, task:, catalog: nil)
  run = ManualAcceptanceSupport.execute_provider_turn_on_conversation!(
    conversation: conversation,
    agent_program_version: agent_program_version,
    content: task.fetch("content"),
    selector_source: task.fetch("selector_source", "manual"),
    selector: task.fetch("selector"),
    catalog: catalog,
    inline_if_queued: false
  )
  workflow_run = run.fetch(:workflow_run).reload
  turn = run.fetch(:turn).reload

  {
    "status" => workflow_run.lifecycle_state == "completed" ? "completed" : "failed",
    "conversation_public_id" => conversation.public_id,
    "turn_public_id" => turn.public_id,
    "workflow_run_public_id" => workflow_run.public_id,
    "runtime_output" => turn.selected_output_message&.content,
    "runtime_error" => workflow_run.lifecycle_state == "completed" ? nil : workflow_run.reload.error_payload,
  }
end

def with_runtime_control_workers!(registrations, index = 0, &block)
  return yield if index >= registrations.length

  registration = registrations.fetch(index)
  ManualAcceptanceSupport.with_fenix_control_worker_for_registration!(
    registration: registration.fetch("runtime_registration"),
    limit: 1,
    env: registration.fetch("runtime_task_env")
  ) do
    with_runtime_control_workers!(registrations, index + 1, &block)
  end
end

repo_root = AcceptanceHarness.repo_root
acceptance_root = AcceptanceHarness.acceptance_root
profile = Acceptance::Perf::Profile.fetch(ENV.fetch("MULTI_FENIX_LOAD_PROFILE", "smoke"))
artifact_stamp = ENV.fetch("MULTI_FENIX_LOAD_ARTIFACT_STAMP") do
  "#{Time.now.utc.strftime("%Y-%m-%d-%H%M%S")}-multi-fenix-core-matrix-load-#{profile.name}"
end
topology = Acceptance::Perf::Topology.build(
  profile: profile,
  repo_root: repo_root,
  acceptance_root: acceptance_root,
  artifact_stamp: artifact_stamp
)
manifest = Acceptance::Perf::WorkloadManifest.for_profile(profile)
provider_catalog_override = Acceptance::Perf::ProviderCatalogOverride.build(
  profile: profile,
  topology: topology,
  rails_root: Rails.root,
  env: Rails.env
)
workload_executor = Acceptance::Perf::WorkloadExecutor.new(
  run_execution_assignment: lambda do |conversation:, registration:, task:, slot_index:|
    execute_mailbox_task_on_conversation!(
      conversation: conversation,
      agent_program_version: registration.fetch("agent_program_version"),
      registration: registration,
      task: task,
      slot_label: registration.fetch("slot_label")
    ).merge("slot_index" => slot_index)
  end,
  run_program_exchange: lambda do |conversation:, registration:, task:, slot_index:|
    execute_program_exchange_task_on_conversation!(
      conversation: conversation,
      agent_program_version: registration.fetch("agent_program_version"),
      task: task,
      catalog: provider_catalog_override&.catalog
    ).merge("slot_index" => slot_index)
  end,
  append_event: lambda do |path:, payload:|
    append_jsonl(path, payload)
  end
)

stack_already_reset = ActiveModel::Type::Boolean.new.cast(
  ENV.fetch("MULTI_FENIX_LOAD_STACK_ALREADY_RESET", "false")
)
ManualAcceptanceSupport.reset_backend_state! unless stack_already_reset
bootstrap = ManualAcceptanceSupport.bootstrap_and_seed!

registration_matrix = Acceptance::Perf::RuntimeRegistrationMatrix.call(
  installation: bootstrap.installation,
  actor: bootstrap.user,
  topology: topology,
  create_external_agent_program: ManualAcceptanceSupport.method(:create_external_agent_program!),
  register_external_runtime: ManualAcceptanceSupport.method(:register_external_runtime!)
)
decorate_boot_states!(registration_matrix, topology)

driver_report =
  if registration_matrix.fetch("runtime_registrations").all? { |entry| entry.fetch("boot_status", "ready") == "ready" }
    with_runtime_control_workers!(registration_matrix.fetch("runtime_registrations")) do
      Acceptance::Perf::WorkloadDriver.call(
        manifest: manifest,
        registration_matrix: registration_matrix,
        create_conversation: lambda do |agent_program_version:|
          ManualAcceptanceSupport.create_conversation!(agent_program_version: agent_program_version)
        end,
        execute_workload_item: lambda do |conversation:, registration:, task:, slot_index:|
          workload_executor.call(
            conversation: conversation,
            registration: registration,
            task: task,
            slot_index: slot_index,
            event_output_path: registration.fetch("event_output_path")
          )
        end
      )
    end
  else
    Acceptance::Perf::WorkloadDriver.call(
      manifest: manifest,
      registration_matrix: registration_matrix,
        create_conversation: lambda do |agent_program_version:|
          ManualAcceptanceSupport.create_conversation!(agent_program_version: agent_program_version)
        end,
        execute_workload_item: lambda do |conversation:, registration:, task:, slot_index:|
          workload_executor.call(
            conversation: conversation,
            registration: registration,
            task: task,
            slot_index: slot_index,
            event_output_path: registration.fetch("event_output_path")
          )
        end
      )
  end

event_paths = [registration_matrix.fetch("core_matrix_events_path")] +
  registration_matrix.fetch("runtime_registrations").map { |entry| entry.fetch("event_output_path") }
existing_event_paths = event_paths.map { |path| Pathname(path) }.select(&:exist?)
metrics = Acceptance::Perf::MetricsAggregator.call(event_paths: existing_event_paths)
gate_result = Acceptance::Perf::GateEvaluator.call(
  profile: profile,
  metrics: metrics,
  structural_failures: driver_report.fetch("structural_failures"),
  completed_workload_items: driver_report.fetch("completed_workload_items")
)
summary = Acceptance::Perf::ReportBuilder.call(
  profile_name: profile.name,
  runtime_count: registration_matrix.fetch("runtime_count"),
  metrics: metrics,
  structural_failures: driver_report.fetch("structural_failures"),
  gate_result: gate_result,
  artifact_paths: {
    "aggregated_metrics" => "evidence/aggregated-metrics.json",
    "runtime_topology" => "evidence/runtime-topology.json",
    "workload_profile" => "evidence/workload-profile.json",
  }
).merge(
  "completed_workload_items" => driver_report.fetch("completed_workload_items"),
  "runtime_count" => registration_matrix.fetch("runtime_count")
)

if gate_result["eligible"]
  summary["outcome"]["classification"] = gate_result["passed"] ? "gate_passed" : "gate_failed"
end

artifact_dir = topology.artifact_root
write_json(artifact_dir.join("evidence", "runtime-topology.json"), {
  "profile_name" => profile.name,
  "runtime_count" => registration_matrix.fetch("runtime_count"),
  "runtime_registrations" => registration_matrix.fetch("runtime_registrations").map do |entry|
    entry.slice("slot_label", "runtime_base_url", "event_output_path", "boot_status", "boot_error")
  end,
})
write_json(artifact_dir.join("evidence", "workload-profile.json"), {
  **manifest.artifact_payload,
  "provider_catalog_override" => provider_catalog_override&.payload,
})
write_json(artifact_dir.join("evidence", "aggregated-metrics.json"), metrics)
write_json(artifact_dir.join("evidence", "run-summary.json"), summary)
write_text(artifact_dir.join("review", "load-summary.md"), Acceptance::BenchmarkReporting.load_summary_markdown(summary))

puts JSON.pretty_generate(summary)
