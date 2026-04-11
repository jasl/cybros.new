#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require_relative '../lib/boot'

def ensure_disposable_nexus_home_root!(path)
  return path if path.basename.to_s.start_with?('acceptance-nexus-home')

  raise(
    'NEXUS_HOME_ROOT must point to a disposable acceptance root ' \
    "(basename must start with acceptance-nexus-home): #{path}"
  )
end

def mailbox_task(content:, mode:, extra_payload: {})
  { content:, mode:, extra_payload: }
end

def run_mailbox_task_on_conversation!(conversation:, registration:, task:)
  run = start_mailbox_turn_workflow!(
    conversation: conversation,
    execution_runtime: registration.execution_runtime,
    task: task
  )
  finalize_mailbox_task_run(run:, conversation:, registration:)
end

def start_mailbox_turn_workflow!(conversation:, execution_runtime:, task:)
  Acceptance::ManualSupport.start_turn_workflow_on_conversation!(
    conversation: conversation,
    execution_runtime: execution_runtime,
    content: task.fetch(:content),
    root_node_key: 'agent_turn_step',
    root_node_type: 'turn_step',
    decision_source: 'agent',
    initial_kind: 'turn_step',
    initial_payload: { 'mode' => task.fetch(:mode) }.merge(task.fetch(:extra_payload, {}))
  )
end

def finalize_mailbox_task_run(run:, conversation:, registration:)
  agent_task_run = Acceptance::ManualSupport.wait_for_agent_task_terminal!(agent_task_run: run.fetch(:agent_task_run))
  terminal_payload = agent_task_run.terminal_payload || {}

  run.merge(
    conversation: conversation.reload,
    execution: execution_summary_for(agent_task_run:, terminal_payload:),
    report_results: report_results_for(agent_task_run:)
  )
end

def execution_summary_for(agent_task_run:, terminal_payload:)
  execution_output =
    if agent_task_run.lifecycle_state == 'completed'
      terminal_payload['output'].presence || terminal_payload.except('terminal_method_id')
    end

  {
    'status' => agent_task_run.lifecycle_state == 'completed' ? 'completed' : 'failed',
    'output' => execution_output,
    'error' => agent_task_run.lifecycle_state == 'completed' ? nil : terminal_payload
  }
end

def report_results_for(agent_task_run:)
  Acceptance::ManualSupport.report_results_for(agent_task_run: agent_task_run)
end

def serialize_run(run)
  serialize_run_identity(run)
    .merge('dag_shape' => Acceptance::ManualSupport.workflow_node_keys(run.fetch(:workflow_run)))
    .merge('conversation_state' => serialize_run_conversation_state(run))
    .merge(serialize_run_execution(run))
    .merge('report_results' => run.fetch(:report_results))
end

def serialize_run_identity(run)
  {
    'conversation_id' => run.fetch(:conversation).public_id,
    'turn_id' => run.fetch(:turn).public_id,
    'workflow_run_id' => run.fetch(:workflow_run).public_id,
    'agent_task_run_id' => run.fetch(:agent_task_run).public_id
  }
end

def serialize_run_conversation_state(run)
  Acceptance::ManualSupport.workflow_state_hash(
    conversation: run.fetch(:conversation),
    workflow_run: run.fetch(:workflow_run),
    turn: run.fetch(:turn),
    agent_task_run: run.fetch(:agent_task_run)
  )
end

def serialize_run_execution(run)
  execution = run.fetch(:execution)

  {
    'runtime_execution_status' => execution.fetch('status'),
    'runtime_output' => execution['output'],
    'runtime_error' => execution['error']
  }
end

def run_passed?(serialized_run, expected_conversation_state)
  serialized_run.fetch('dag_shape') == ['agent_turn_step'] &&
    expected_conversation_state.all? do |key, value|
      serialized_run.fetch('conversation_state')[key] == value
    end
end

agent_base_url = ENV.fetch('FENIX_RUNTIME_BASE_URL', 'http://127.0.0.1:3101')
runtime_base_url = ENV.fetch('NEXUS_RUNTIME_BASE_URL', 'http://127.0.0.1:3301')
nexus_home_root = ensure_disposable_nexus_home_root!(
  Pathname.new(
    ENV.fetch('NEXUS_HOME_ROOT', Rails.root.join('tmp/acceptance-nexus-home').to_s)
  ).expand_path
)
ENV['NEXUS_HOME_ROOT'] = nexus_home_root.to_s

FileUtils.rm_rf(nexus_home_root)
FileUtils.mkdir_p(nexus_home_root)

Acceptance::ManualSupport.reset_backend_state!
bootstrap = Acceptance::ManualSupport.bootstrap_and_seed!

external_program_a = Acceptance::ManualSupport.create_external_agent!(
  installation: bootstrap.installation,
  actor: bootstrap.user,
  key: 'fenix-skills-program-a',
  display_name: 'Fenix Skills Runtime A'
)
external_program_b = Acceptance::ManualSupport.create_external_agent!(
  installation: bootstrap.installation,
  actor: bootstrap.user,
  key: 'fenix-skills-program-b',
  display_name: 'Fenix Skills Runtime B'
)

registration_a = Acceptance::ManualSupport.register_external_runtime!(
  enrollment_token: external_program_a.fetch(:enrollment_token),
  runtime_base_url: runtime_base_url,
  agent_base_url: agent_base_url,
  execution_runtime_fingerprint: 'acceptance-fenix-skills-environment-a',
  fingerprint: 'acceptance-fenix-skills-a-v1'
)
registration_b = Acceptance::ManualSupport.register_external_runtime!(
  enrollment_token: external_program_b.fetch(:enrollment_token),
  runtime_base_url: runtime_base_url,
  agent_base_url: agent_base_url,
  execution_runtime_fingerprint: 'acceptance-fenix-skills-environment-b',
  fingerprint: 'acceptance-fenix-skills-b-v1'
)

agent_snapshot_a = registration_a.agent_snapshot
agent_snapshot_b = registration_b.agent_snapshot

source_root = Rails.root.join('tmp/acceptance-portable-notes-src/portable-notes')
FileUtils.rm_rf(source_root.parent)
FileUtils.mkdir_p(source_root.join('references'))
File.write(
  source_root.join('SKILL.md'),
  <<~MD
    ---
    name: portable-notes
    description: Capture notes.
    ---

    # Portable Notes

    Write portable notes.
  MD
)
File.write(source_root.join('references', 'checklist.md'), "# Checklist\n")

conversation_a = Acceptance::ManualSupport.create_conversation!(agent_snapshot: agent_snapshot_a)
conversation_b = Acceptance::ManualSupport.create_conversation!(agent_snapshot: agent_snapshot_a)
conversation_c = Acceptance::ManualSupport.create_conversation!(agent_snapshot: agent_snapshot_b)

install_run = nil
same_program_load_run = nil
same_program_read_run = nil
different_program_load_run = nil

Acceptance::ManualSupport.with_fenix_control_worker!(
  agent_connection_credential: registration_a.agent_connection_credential,
  limit: 1,
  inline: true
) do
  Acceptance::ManualSupport.with_fenix_control_worker!(
    agent_connection_credential: registration_b.agent_connection_credential,
    limit: 1,
    inline: true
  ) do
    Acceptance::ManualSupport.with_nexus_control_worker_for_registration!(
      registration: registration_a,
      limit: 1,
      inline: true,
      env: { 'NEXUS_HOME_ROOT' => nexus_home_root.to_s }
    ) do
      Acceptance::ManualSupport.with_nexus_control_worker_for_registration!(
        registration: registration_b,
        limit: 1,
        inline: true,
        env: { 'NEXUS_HOME_ROOT' => nexus_home_root.to_s }
      ) do
        install_run = run_mailbox_task_on_conversation!(
          conversation: conversation_a.fetch(:conversation),
          registration: registration_a,
          task: mailbox_task(
            content: 'Install portable-notes in conversation A.',
            mode: 'skills_install',
            extra_payload: { 'source_path' => source_root.to_s }
          )
        )
        same_program_load_run = run_mailbox_task_on_conversation!(
          conversation: conversation_b.fetch(:conversation),
          registration: registration_a,
          task: mailbox_task(
            content: 'Load portable-notes from conversation B.',
            mode: 'skills_load',
            extra_payload: { 'skill_name' => 'portable-notes' }
          )
        )
        same_program_read_run = run_mailbox_task_on_conversation!(
          conversation: conversation_b.fetch(:conversation),
          registration: registration_a,
          task: mailbox_task(
            content: 'Read portable-notes checklist from conversation B.',
            mode: 'skills_read_file',
            extra_payload: {
              'skill_name' => 'portable-notes',
              'relative_path' => 'references/checklist.md'
            }
          )
        )
        different_program_load_run = run_mailbox_task_on_conversation!(
          conversation: conversation_c.fetch(:conversation),
          registration: registration_b,
          task: mailbox_task(
            content: 'Load portable-notes from conversation C on a different program.',
            mode: 'skills_load',
            extra_payload: { 'skill_name' => 'portable-notes' }
          )
        )
      end
    end
  end
end

expected_conversation_state = {
  'conversation_state' => 'active',
  'workflow_lifecycle_state' => 'completed',
  'workflow_wait_state' => 'ready',
  'turn_lifecycle_state' => 'active',
  'agent_task_run_state' => 'completed'
}.freeze
expected_isolation_failure_state = {
  'conversation_state' => 'active',
  'workflow_lifecycle_state' => 'failed',
  'workflow_wait_state' => 'ready',
  'turn_lifecycle_state' => 'active',
  'agent_task_run_state' => 'failed'
}.freeze

serialized_install_run = serialize_run(install_run)
serialized_same_program_load_run = serialize_run(same_program_load_run)
serialized_same_program_read_run = serialize_run(same_program_read_run)
serialized_different_program_load_run = serialize_run(different_program_load_run)

shared_conversation_success = {
  'passed' => run_passed?(serialized_same_program_load_run, expected_conversation_state) &&
              run_passed?(serialized_same_program_read_run, expected_conversation_state) &&
              same_program_load_run.fetch(:conversation).public_id ==
              same_program_read_run.fetch(:conversation).public_id &&
              same_program_load_run.fetch(:execution).dig('output', 'name') == 'portable-notes' &&
              same_program_read_run.fetch(:execution).dig('output', 'content') == "# Checklist\n",
  'conversation_id' => conversation_b.fetch(:conversation).public_id,
  'load_name' => same_program_load_run.fetch(:execution).dig('output', 'name'),
  'read_content' => same_program_read_run.fetch(:execution).dig('output', 'content')
}.freeze

different_program_failure = {
  'passed' => run_passed?(serialized_different_program_load_run, expected_isolation_failure_state) &&
              different_program_load_run.fetch(:execution).fetch('status') == 'failed' &&
              different_program_load_run.fetch(:execution).dig('error', 'code') == 'skill_not_found',
  'conversation_id' => conversation_c.fetch(:conversation).public_id,
  'status' => different_program_load_run.fetch(:execution).fetch('status'),
  'error' => different_program_load_run.fetch(:execution).fetch('error')
}.freeze

install_scope_root = install_run.fetch(:execution).dig('output', 'live_root')
passed = run_passed?(serialized_install_run, expected_conversation_state) &&
         shared_conversation_success.fetch('passed') &&
         different_program_failure.fetch('passed')

Acceptance::ManualSupport.write_json(
  {
    'scenario' => 'fenix_skills_validation',
    'passed' => passed,
    'proof_artifact_path' => nil,
    'agent_base_url' => agent_base_url,
    'runtime_base_url' => runtime_base_url,
    'nexus_home_root' => nexus_home_root.to_s,
    'install_scope_root' => install_scope_root,
    'shared_conversation_success' => shared_conversation_success,
    'different_program_failure' => different_program_failure,
    'registrations' => {
      'program_a' => {
        'agent_snapshot_id' => agent_snapshot_a.public_id,
        'execution_runtime_id' => registration_a.execution_runtime&.public_id,
        'agent_connection_id' => registration_a.agent_connection_id,
        'execution_runtime_connection_id' => registration_a.execution_runtime_connection_id
      },
      'program_b' => {
        'agent_snapshot_id' => agent_snapshot_b.public_id,
        'execution_runtime_id' => registration_b.execution_runtime&.public_id,
        'agent_connection_id' => registration_b.agent_connection_id,
        'execution_runtime_connection_id' => registration_b.execution_runtime_connection_id
      }
    },
    'conversation_a' => {
      'install_run' => serialized_install_run,
      'conversation_id' => conversation_a.fetch(:conversation).public_id
    },
    'conversation_b' => {
      'load_run' => serialized_same_program_load_run,
      'read_run' => serialized_same_program_read_run,
      'conversation_id' => conversation_b.fetch(:conversation).public_id
    },
    'conversation_c' => {
      'load_run' => serialized_different_program_load_run,
      'conversation_id' => conversation_c.fetch(:conversation).public_id
    }
  }
)
