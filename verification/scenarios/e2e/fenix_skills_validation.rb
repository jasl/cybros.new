#!/usr/bin/env ruby
# VERIFICATION_MODE: hybrid_app_api
# This scenario must use app_api where a product/operator surface exists and only keep internal hooks for skills mailbox task modes that have no product endpoint yet.
# frozen_string_literal: true

require 'fileutils'
$LOAD_PATH.unshift(File.expand_path("../../lib", __dir__))
require "verification/hosted/core_matrix"

def ensure_disposable_nexus_home_root!(path)
  return path if path.basename.to_s.start_with?('verification-nexus-home')

  raise(
    'NEXUS_HOME_ROOT must point to a disposable verification root ' \
    "(basename must start with verification-nexus-home): #{path}"
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
  Verification::ManualSupport.start_turn_workflow_on_conversation!(
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
  agent_task_run = Verification::ManualSupport.wait_for_agent_task_terminal!(agent_task_run: run.fetch(:agent_task_run))
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
  Verification::ManualSupport.report_results_for(agent_task_run: agent_task_run)
end

def observe_run_via_app_api(run:, session_token:, artifact_dir:)
  conversation_id = run.fetch(:conversation).public_id
  turn_id = run.fetch(:turn).public_id
  debug_export_path = artifact_dir.join('exports', "#{turn_id}-conversation-debug-export.zip")
  diagnostics = Verification::ManualSupport.app_api_conversation_diagnostics_show!(
    conversation_id: conversation_id,
    session_token: session_token
  )
  turns_payload = Verification::ManualSupport.app_api_conversation_diagnostics_turns!(
    conversation_id: conversation_id,
    session_token: session_token
  )
  materialized_diagnostics = Verification::ManualSupport.wait_for_app_api_conversation_diagnostics_materialized!(
    conversation_id: conversation_id,
    session_token: session_token
  )
  debug_export_download = Verification::ManualSupport.app_api_debug_export_conversation!(
    conversation_id: conversation_id,
    session_token: session_token,
    destination_path: debug_export_path
  )
  debug_payload = Verification::ManualSupport.extract_debug_export_payload!(
    debug_export_download.dig('download', 'path')
  )
  workflow_run = debug_payload.fetch('workflow_runs')
    .select { |candidate| candidate.fetch('turn_id') == turn_id }
    .max_by { |candidate| [candidate.fetch('created_at').to_s, candidate.fetch('workflow_run_id')] } || {}
  materialized_turn_snapshot = materialized_diagnostics.fetch('turns').fetch('items')
    .find { |item| item.fetch('turn_id') == turn_id }
  selected_output_message = debug_payload.fetch('conversation_payload')
    .fetch('messages')
    .reverse
    .find { |message| message.fetch('turn_public_id') == turn_id && message.fetch('role') == 'assistant' }
  truth_state = {
    'conversation_state' => run.fetch(:conversation).reload.lifecycle_state,
    'workflow_lifecycle_state' => workflow_run.fetch('lifecycle_state'),
    'workflow_wait_state' => workflow_run.fetch('wait_state'),
    'turn_lifecycle_state' => run.fetch(:turn).reload.lifecycle_state,
    'agent_task_run_state' => run.fetch(:agent_task_run).reload.lifecycle_state,
    'selected_output_message_id' => selected_output_message&.fetch('message_public_id', nil),
    'selected_output_content' => selected_output_message&.fetch('content', nil)
  }.compact
  diagnostics_contract_passed =
    %w[pending ready stale].include?(diagnostics.fetch('diagnostics_status')) &&
    %w[pending ready stale].include?(turns_payload.fetch('diagnostics_status')) &&
    %w[ready stale].include?(materialized_diagnostics.dig('conversation', 'diagnostics_status')) &&
    %w[ready stale].include?(materialized_diagnostics.dig('turns', 'diagnostics_status')) &&
    materialized_diagnostics.dig('conversation', 'snapshot', 'lifecycle_state') == truth_state['conversation_state'] &&
    materialized_turn_snapshot.present? &&
    materialized_turn_snapshot.fetch('lifecycle_state') == truth_state['turn_lifecycle_state']

  {
    'dag_shape' => debug_payload.fetch('workflow_nodes')
      .select { |node| node.fetch('turn_id') == turn_id }
      .sort_by { |node| [node.fetch('ordinal'), node.fetch('created_at').to_s] }
      .map { |node| node.fetch('node_key') },
    'conversation_state' => truth_state,
    'workflow_run_id' => workflow_run.fetch('workflow_run_id', nil),
    'debug_export_path' => debug_export_path.to_s,
    'diagnostics_initial_status' => diagnostics.fetch('diagnostics_status'),
    'diagnostics_turns_initial_status' => turns_payload.fetch('diagnostics_status'),
    'diagnostics_eventual_status' => materialized_diagnostics.dig('conversation', 'diagnostics_status'),
    'diagnostics_turns_eventual_status' => materialized_diagnostics.dig('turns', 'diagnostics_status'),
    'diagnostics_projection_contract_passed' => diagnostics_contract_passed
  }
end

def serialize_run(run, session_token:, artifact_dir:)
  observed = observe_run_via_app_api(run:, session_token:, artifact_dir:)

  serialize_run_identity(run)
    .merge('workflow_run_id' => observed.fetch('workflow_run_id'))
    .merge('dag_shape' => observed.fetch('dag_shape'))
    .merge('conversation_state' => observed.fetch('conversation_state'))
    .merge(
      'diagnostics_initial_status' => observed.fetch('diagnostics_initial_status'),
      'diagnostics_turns_initial_status' => observed.fetch('diagnostics_turns_initial_status'),
      'diagnostics_eventual_status' => observed.fetch('diagnostics_eventual_status'),
      'diagnostics_turns_eventual_status' => observed.fetch('diagnostics_turns_eventual_status'),
      'diagnostics_projection_contract_passed' => observed.fetch('diagnostics_projection_contract_passed')
    )
    .merge(serialize_run_execution(run))
    .merge('report_results' => run.fetch(:report_results))
    .merge('debug_export_path' => observed.fetch('debug_export_path'))
end

def serialize_run_identity(run)
  {
    'conversation_id' => run.fetch(:conversation).public_id,
    'turn_id' => run.fetch(:turn).public_id,
    'agent_task_run_id' => run.fetch(:agent_task_run).public_id
  }
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
    serialized_run.fetch('diagnostics_projection_contract_passed') &&
    expected_conversation_state.all? do |key, value|
      serialized_run.fetch('conversation_state')[key] == value
    end
end

agent_base_url = ENV.fetch('FENIX_RUNTIME_BASE_URL', 'http://127.0.0.1:3101')
runtime_base_url = ENV.fetch('NEXUS_RUNTIME_BASE_URL', 'http://127.0.0.1:3301')
artifact_stamp = ENV.fetch('FENIX_SKILLS_ARTIFACT_STAMP') do
  "#{Time.current.strftime("%Y-%m-%d-%H%M%S")}-fenix-skills-validation"
end
artifact_dir = Verification.repo_root.join('verification', 'artifacts', artifact_stamp)
nexus_home_root = ensure_disposable_nexus_home_root!(
  Pathname.new(
    ENV.fetch('NEXUS_HOME_ROOT', Rails.root.join('tmp/verification-nexus-home').to_s)
  ).expand_path
)
ENV['NEXUS_HOME_ROOT'] = nexus_home_root.to_s

FileUtils.rm_rf(nexus_home_root)
FileUtils.mkdir_p(nexus_home_root)

Verification::ManualSupport.reset_backend_state!
bootstrap = Verification::ManualSupport.bootstrap_and_seed!
app_api_session_token = Verification::ManualSupport.issue_app_api_session_token!(user: bootstrap.user)
FileUtils.rm_rf(artifact_dir)
FileUtils.mkdir_p(artifact_dir)

bring_your_own_agent_a = Verification::ManualSupport.create_bring_your_own_agent!(
  installation: bootstrap.installation,
  actor: bootstrap.user,
  key: 'fenix-skills-agent-a',
  display_name: 'Fenix Skills Runtime A'
)
bring_your_own_agent_b = Verification::ManualSupport.create_bring_your_own_agent!(
  installation: bootstrap.installation,
  actor: bootstrap.user,
  key: 'fenix-skills-agent-b',
  display_name: 'Fenix Skills Runtime B'
)

registration_a = Verification::ManualSupport.register_bring_your_own_runtime!(
  onboarding_token: bring_your_own_agent_a.fetch(:onboarding_token),
  runtime_base_url: runtime_base_url,
  agent_base_url: agent_base_url,
  execution_runtime_fingerprint: 'verification-fenix-skills-environment-a'
)
registration_b = Verification::ManualSupport.register_bring_your_own_runtime!(
  onboarding_token: bring_your_own_agent_b.fetch(:onboarding_token),
  runtime_base_url: runtime_base_url,
  agent_base_url: agent_base_url,
  execution_runtime_fingerprint: 'verification-fenix-skills-environment-b'
)

agent_definition_version_a = registration_a.agent_definition_version
agent_definition_version_b = registration_b.agent_definition_version

source_root = Rails.root.join('tmp/verification-portable-notes-src/portable-notes')
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

conversation_a = Verification::ManualSupport.create_conversation!(agent_definition_version: agent_definition_version_a)
conversation_b = Verification::ManualSupport.create_conversation!(agent_definition_version: agent_definition_version_a)
conversation_c = Verification::ManualSupport.create_conversation!(agent_definition_version: agent_definition_version_b)

install_run = nil
same_agent_load_run = nil
same_agent_read_run = nil
different_agent_load_run = nil

Verification::ManualSupport.with_fenix_control_worker!(
  agent_connection_credential: registration_a.agent_connection_credential,
  limit: 1,
  inline: true
) do
  Verification::ManualSupport.with_fenix_control_worker!(
    agent_connection_credential: registration_b.agent_connection_credential,
    limit: 1,
    inline: true
  ) do
    Verification::ManualSupport.with_nexus_control_worker_for_registration!(
      registration: registration_a,
      limit: 1,
      inline: true,
      env: { 'NEXUS_HOME_ROOT' => nexus_home_root.to_s }
    ) do
      Verification::ManualSupport.with_nexus_control_worker_for_registration!(
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
        same_agent_load_run = run_mailbox_task_on_conversation!(
          conversation: conversation_b.fetch(:conversation),
          registration: registration_a,
          task: mailbox_task(
            content: 'Load portable-notes from conversation B.',
            mode: 'skills_load',
            extra_payload: { 'skill_name' => 'portable-notes' }
          )
        )
        same_agent_read_run = run_mailbox_task_on_conversation!(
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
        different_agent_load_run = run_mailbox_task_on_conversation!(
          conversation: conversation_c.fetch(:conversation),
          registration: registration_b,
          task: mailbox_task(
            content: 'Load portable-notes from conversation C on a different agent.',
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

serialized_install_run = serialize_run(install_run, session_token: app_api_session_token, artifact_dir: artifact_dir)
serialized_same_agent_load_run = serialize_run(same_agent_load_run, session_token: app_api_session_token, artifact_dir: artifact_dir)
serialized_same_agent_read_run = serialize_run(same_agent_read_run, session_token: app_api_session_token, artifact_dir: artifact_dir)
serialized_different_agent_load_run = serialize_run(different_agent_load_run, session_token: app_api_session_token, artifact_dir: artifact_dir)

shared_conversation_success = {
  'passed' => run_passed?(serialized_same_agent_load_run, expected_conversation_state) &&
              run_passed?(serialized_same_agent_read_run, expected_conversation_state) &&
              same_agent_load_run.fetch(:conversation).public_id ==
              same_agent_read_run.fetch(:conversation).public_id &&
              same_agent_load_run.fetch(:execution).dig('output', 'name') == 'portable-notes' &&
              same_agent_read_run.fetch(:execution).dig('output', 'content') == "# Checklist\n",
  'conversation_id' => conversation_b.fetch(:conversation).public_id,
  'load_name' => same_agent_load_run.fetch(:execution).dig('output', 'name'),
  'read_content' => same_agent_read_run.fetch(:execution).dig('output', 'content')
}.freeze

different_agent_failure = {
  'passed' => run_passed?(serialized_different_agent_load_run, expected_isolation_failure_state) &&
              different_agent_load_run.fetch(:execution).fetch('status') == 'failed' &&
              different_agent_load_run.fetch(:execution).dig('error', 'code') == 'skill_not_found',
  'conversation_id' => conversation_c.fetch(:conversation).public_id,
  'status' => different_agent_load_run.fetch(:execution).fetch('status'),
  'error' => different_agent_load_run.fetch(:execution).fetch('error')
}.freeze

install_scope_root = install_run.fetch(:execution).dig('output', 'live_root')
passed = run_passed?(serialized_install_run, expected_conversation_state) &&
         shared_conversation_success.fetch('passed') &&
         different_agent_failure.fetch('passed')

Verification::ManualSupport.write_json(
  {
    'scenario' => 'fenix_skills_validation',
    'passed' => passed,
    'proof_artifact_path' => artifact_dir.to_s,
    'agent_base_url' => agent_base_url,
    'runtime_base_url' => runtime_base_url,
    'nexus_home_root' => nexus_home_root.to_s,
    'install_scope_root' => install_scope_root,
    'shared_conversation_success' => shared_conversation_success,
    'different_agent_failure' => different_agent_failure,
    'registrations' => {
      'agent_a' => {
        'agent_definition_version_id' => agent_definition_version_a.public_id,
        'execution_runtime_id' => registration_a.execution_runtime&.public_id,
        'agent_connection_id' => registration_a.agent_connection_id,
        'execution_runtime_connection_id' => registration_a.execution_runtime_connection_id
      },
      'agent_b' => {
        'agent_definition_version_id' => agent_definition_version_b.public_id,
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
      'load_run' => serialized_same_agent_load_run,
      'read_run' => serialized_same_agent_read_run,
      'conversation_id' => conversation_b.fetch(:conversation).public_id
    },
    'conversation_c' => {
      'load_run' => serialized_different_agent_load_run,
      'conversation_id' => conversation_c.fetch(:conversation).public_id
    }
  }
)
