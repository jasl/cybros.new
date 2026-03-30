#!/usr/bin/env ruby

require "fileutils"
require_relative "../manual_acceptance_support"

runtime_base_url = ENV.fetch("FENIX_RUNTIME_BASE_URL", "http://127.0.0.1:3102")
live_root = ENV.fetch("FENIX_LIVE_SKILLS_ROOT", "/tmp/phase2-fenix-live-skills")
staging_root = ENV.fetch("FENIX_STAGING_SKILLS_ROOT", "/tmp/phase2-fenix-staging")
backup_root = ENV.fetch("FENIX_BACKUP_SKILLS_ROOT", "/tmp/phase2-fenix-backups")

ManualAcceptanceSupport.reset_backend_state!
bootstrap = ManualAcceptanceSupport.bootstrap_and_seed!
external = ManualAcceptanceSupport.create_external_agent_installation!(
  installation: bootstrap.installation,
  actor: bootstrap.user,
  key: "fenix-skills",
  display_name: "Fenix Skills Runtime"
)
registration = ManualAcceptanceSupport.register_external_runtime!(
  enrollment_token: external.fetch(:enrollment_token),
  runtime_base_url: runtime_base_url,
  environment_fingerprint: "phase2-fenix-skills-environment",
  fingerprint: "phase2-fenix-skills-v1"
)

FileUtils.rm_rf(Dir.glob(File.join(live_root, "*")))
FileUtils.rm_rf(Dir.glob(File.join(staging_root, "*")))
FileUtils.rm_rf(Dir.glob(File.join(backup_root, "*")))

source_root = Rails.root.join("tmp", "phase2-portable-notes-src", "portable-notes")
FileUtils.rm_rf(source_root.parent)
FileUtils.mkdir_p(source_root.join("references"))
File.write(
  source_root.join("SKILL.md"),
  <<~MD
    ---
    name: portable-notes
    description: Capture notes.
    ---

    # Portable Notes

    Write portable notes.
  MD
)
File.write(source_root.join("references", "checklist.md"), "# Checklist\n")

catalog_run = ManualAcceptanceSupport.run_fenix_mailbox_task!(
  deployment: registration.fetch(:deployment),
  machine_credential: registration.fetch(:machine_credential),
  runtime_base_url: runtime_base_url,
  content: "List available skills.",
  mode: "skills_catalog_list"
)
load_system_run = ManualAcceptanceSupport.run_fenix_mailbox_task!(
  deployment: registration.fetch(:deployment),
  machine_credential: registration.fetch(:machine_credential),
  runtime_base_url: runtime_base_url,
  content: "Load deploy-agent.",
  mode: "skills_load",
  extra_payload: { "skill_name" => "deploy-agent" }
)
read_system_run = ManualAcceptanceSupport.run_fenix_mailbox_task!(
  deployment: registration.fetch(:deployment),
  machine_credential: registration.fetch(:machine_credential),
  runtime_base_url: runtime_base_url,
  content: "Read deploy-agent script.",
  mode: "skills_read_file",
  extra_payload: {
    "skill_name" => "deploy-agent",
    "relative_path" => "scripts/deploy_agent.rb",
  }
)
install_run = ManualAcceptanceSupport.run_fenix_mailbox_task!(
  deployment: registration.fetch(:deployment),
  machine_credential: registration.fetch(:machine_credential),
  runtime_base_url: runtime_base_url,
  content: "Install portable-notes skill.",
  mode: "skills_install",
  extra_payload: { "source_path" => source_root.to_s }
)
load_live_run = ManualAcceptanceSupport.run_fenix_mailbox_task!(
  deployment: registration.fetch(:deployment),
  machine_credential: registration.fetch(:machine_credential),
  runtime_base_url: runtime_base_url,
  content: "Load portable-notes on the next top-level turn.",
  mode: "skills_load",
  extra_payload: { "skill_name" => "portable-notes" }
)
read_live_run = ManualAcceptanceSupport.run_fenix_mailbox_task!(
  deployment: registration.fetch(:deployment),
  machine_credential: registration.fetch(:machine_credential),
  runtime_base_url: runtime_base_url,
  content: "Read portable-notes checklist.",
  mode: "skills_read_file",
  extra_payload: {
    "skill_name" => "portable-notes",
    "relative_path" => "references/checklist.md",
  }
)

expected_conversation_state = {
  "conversation_state" => "active",
  "workflow_lifecycle_state" => "completed",
  "workflow_wait_state" => "ready",
  "turn_lifecycle_state" => "active",
  "agent_task_run_state" => "completed",
}.freeze

serialize_run = lambda do |run|
  {
    "conversation_id" => run.fetch(:conversation).public_id,
    "turn_id" => run.fetch(:turn).public_id,
    "workflow_run_id" => run.fetch(:workflow_run).public_id,
    "agent_task_run_id" => run.fetch(:agent_task_run).public_id,
    "dag_shape" => ManualAcceptanceSupport.workflow_node_keys(run.fetch(:workflow_run)),
    "conversation_state" => ManualAcceptanceSupport.workflow_state_hash(
      conversation: run.fetch(:conversation),
      workflow_run: run.fetch(:workflow_run),
      turn: run.fetch(:turn),
      agent_task_run: run.fetch(:agent_task_run)
    ),
    "runtime_execution_status" => run.fetch(:execution).fetch("status"),
    "runtime_output" => run.fetch(:execution)["output"],
    "report_results" => run.fetch(:report_results),
  }
end

scenario_12_runs = [
  serialize_run.call(catalog_run),
  serialize_run.call(load_system_run),
  serialize_run.call(read_system_run),
]
scenario_13_runs = [
  serialize_run.call(install_run),
  serialize_run.call(load_live_run),
  serialize_run.call(read_live_run),
]

scenario_runs_passed = lambda do |runs|
  runs.all? do |serialized_run|
    serialized_run.fetch("dag_shape") == ["agent_turn_step"] &&
      serialized_run.fetch("conversation_state") == expected_conversation_state
  end
end

ManualAcceptanceSupport.write_json(
  {
    "scenario" => "fenix_skills_validation",
    "passed" => scenario_runs_passed.call(scenario_12_runs) && scenario_runs_passed.call(scenario_13_runs),
    "proof_artifact_path" => nil,
    "deployment_id" => registration.fetch(:deployment).public_id,
    "execution_environment_id" => registration.fetch(:deployment).execution_environment.public_id,
    "heartbeat_bootstrap_state" => registration.fetch(:heartbeat).fetch("bootstrap_state"),
    "scenario_12" => {
      "passed" => scenario_runs_passed.call(scenario_12_runs),
      "expected_dag_shape" => ["agent_turn_step"],
      "expected_conversation_state" => expected_conversation_state,
      "catalog_run" => scenario_12_runs[0],
      "load_system_run" => scenario_12_runs[1],
      "read_system_run" => scenario_12_runs[2],
      "catalog_names" => Array(catalog_run.fetch(:execution)["output"]).map { |entry| [entry["name"], entry["source_kind"], entry["active"]] },
      "load_system_name" => load_system_run.fetch(:execution).dig("output", "name"),
      "load_system_files" => load_system_run.fetch(:execution).dig("output", "files"),
      "read_system_content" => read_system_run.fetch(:execution).dig("output", "content"),
    },
    "scenario_13" => {
      "passed" => scenario_runs_passed.call(scenario_13_runs),
      "expected_dag_shape" => ["agent_turn_step"],
      "expected_conversation_state" => expected_conversation_state,
      "install_run" => scenario_13_runs[0],
      "load_live_run" => scenario_13_runs[1],
      "read_live_run" => scenario_13_runs[2],
      "install_activation_state" => install_run.fetch(:execution).dig("output", "activation_state"),
      "install_live_root" => install_run.fetch(:execution).dig("output", "live_root"),
      "load_live_name" => load_live_run.fetch(:execution).dig("output", "name"),
      "load_live_files" => load_live_run.fetch(:execution).dig("output", "files"),
      "read_live_content" => read_live_run.fetch(:execution).dig("output", "content"),
    },
  }
)
