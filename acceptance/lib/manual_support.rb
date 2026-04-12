# frozen_string_literal: true

ENV['RAILS_ENV'] ||= 'development'

require 'action_controller'
require 'fileutils'
require 'json'
require 'net/http'
require 'open3'
require 'stringio'
require 'uri'
require 'timeout'
require_relative 'manual_support/runtime_registration'
require_relative '../../core_matrix/config/environment' unless defined?(Rails.application)

# Acceptance-owned helper surface for operator and scenario validation flows.
# rubocop:disable Metrics/ModuleLength, Metrics/MethodLength, Metrics/AbcSize, Metrics/ParameterLists
module Acceptance
  # Acceptance-owned helper surface for operator and scenario validation flows.
  module ManualSupport
    module_function

    CONTROL_BASE_URL = ENV.fetch('CORE_MATRIX_BASE_URL', 'http://127.0.0.1:3000')

    def reset_backend_state!
      disconnect_application_record!
      run_database_reset_command!
      reconnect_application_record!
    end

    def bootstrap_and_seed!(bundled_agent_configuration: { enabled: false })
      bootstrap = Installations::BootstrapFirstAdmin.call(
        name: 'Primary Installation',
        email: 'admin@example.com',
        password: 'Password123!',
        password_confirmation: 'Password123!',
        display_name: 'Primary Admin',
        bundled_agent_configuration: bundled_agent_configuration
      )

      silence_stdout do
        load Rails.root.join('db/seeds.rb')
      end
      bootstrap
    end

    def token_headers(agent_connection_credential)
      {
        'Authorization' => ActionController::HttpAuthentication::Token.encode_credentials(agent_connection_credential)
      }
    end

    def control_url(path)
      "#{CONTROL_BASE_URL}#{path}"
    end

    def http_get_response(url, headers: {})
      uri = URI(url)
      request = Net::HTTP::Get.new(uri)
      headers.each { |key, value| request[key] = value }

      response = Net::HTTP.start(uri.host, uri.port) do |http|
        http.request(request)
      end

      [response, response.body.to_s]
    end

    def http_get_json(url, headers: {})
      response, body = http_get_response(url, headers:)
      parsed = body.empty? ? {} : JSON.parse(body)
      raise "HTTP #{response.code}: #{body}" unless response.code.to_i.between?(200, 299)

      parsed
    end

    def http_post_json(url, payload, headers: {})
      uri = URI(url)
      request = Net::HTTP::Post.new(uri)
      request['Content-Type'] = 'application/json'
      headers.each { |key, value| request[key] = value }
      request.body = JSON.generate(payload)
      execute_http(uri, request)
    end

    def http_post_multipart_json(url, params:, file_param:, file_path:, content_type: 'application/zip', headers: {})
      uri = URI(url)
      request = Net::HTTP::Post.new(uri)
      headers.each { |key, value| request[key] = value }

      response = nil
      body = nil

      File.open(file_path, 'rb') do |io|
        request.set_form(
          params.map do |key, value|
            [key.to_s, value]
          end + [[file_param.to_s, io, { filename: File.basename(file_path), content_type: content_type }]],
          'multipart/form-data'
        )

        response = Net::HTTP.start(uri.host, uri.port) do |http|
          http.request(request)
        end
        body = response.body.to_s
      end

      parsed = body.empty? ? {} : JSON.parse(body)
      raise "HTTP #{response.code}: #{body}" unless response.code.to_i.between?(200, 299)

      parsed
    end

    def http_download!(url, headers:, destination_path:)
      response, body = http_get_response(url, headers:)
      raise "HTTP #{response.code}: #{body}" unless response.code.to_i.between?(200, 299)

      FileUtils.mkdir_p(File.dirname(destination_path))
      File.binwrite(destination_path, body)

      {
        'path' => destination_path.to_s,
        'content_type' => response['Content-Type'],
        'content_disposition' => response['Content-Disposition'],
        'byte_size' => body.bytesize
      }
    end

    def execute_http(uri, request)
      response = Net::HTTP.start(uri.host, uri.port) do |http|
        http.request(request)
      end
      body = response.body.to_s
      parsed = body.empty? ? {} : JSON.parse(body)
      raise "HTTP #{response.code}: #{body}" unless response.code.to_i.between?(200, 299)

      parsed
    end

    def live_manifest(base_url:)
      http_get_json("#{base_url}/runtime/manifest")
    end

    def app_api_get_json(path, agent_connection_credential:, params: {})
      query = params.present? ? "?#{URI.encode_www_form(params.transform_keys(&:to_s))}" : ''
      http_get_json(control_url(path) + query, headers: token_headers(agent_connection_credential))
    end

    def app_api_post_json(path, payload, agent_connection_credential:)
      http_post_json(control_url(path), payload, headers: token_headers(agent_connection_credential))
    end

    def app_api_post_multipart_json(path, params:, file_param:, file_path:, agent_connection_credential:,
                                    content_type: 'application/zip')
      http_post_multipart_json(
        control_url(path),
        params: params,
        file_param: file_param,
        file_path: file_path,
        content_type: content_type,
        headers: token_headers(agent_connection_credential)
      )
    end

    def app_api_download!(path, destination_path:, agent_connection_credential:)
      http_download!(
        control_url(path),
        headers: token_headers(agent_connection_credential),
        destination_path: destination_path
      )
    end

    def wait_for_app_api_request_terminal!(path:, request_key:, agent_connection_credential:, terminal_states:,
                                           timeout_seconds: 30, poll_interval_seconds: 0.2)
      deadline_at = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout_seconds
      terminal_states = Array(terminal_states)

      loop do
        payload = app_api_get_json(path, agent_connection_credential:)
        request = payload.fetch(request_key)
        return payload if terminal_states.include?(request.fetch('lifecycle_state'))

        if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline_at
          raise "timed out waiting for app api request #{path} to reach #{terminal_states.join(', ')}"
        end

        sleep(poll_interval_seconds)
      end
    end

    def app_api_conversation_transcript!(conversation_id:, agent_connection_credential:, cursor: nil, limit: nil)
      app_api_get_json(
        '/app_api/conversation_transcripts',
        agent_connection_credential:,
        params: {
          conversation_id: conversation_id,
          cursor: cursor,
          limit: limit
        }.compact
      )
    end

    def app_api_conversation_diagnostics_show!(conversation_id:, agent_connection_credential:)
      app_api_get_json(
        '/app_api/conversation_diagnostics/show',
        agent_connection_credential:,
        params: { conversation_id: conversation_id }
      )
    end

    def app_api_conversation_diagnostics_turns!(conversation_id:, agent_connection_credential:)
      app_api_get_json(
        '/app_api/conversation_diagnostics/turns',
        agent_connection_credential:,
        params: { conversation_id: conversation_id }
      )
    end

    def create_conversation_supervision_session!(conversation_id:, actor:, responder_strategy: 'summary_model')
      conversation = Conversation.find_by_public_id!(conversation_id)
      session = EmbeddedAgents::ConversationSupervision::CreateSession.call(
        actor: actor,
        conversation: conversation,
        responder_strategy: responder_strategy
      )

      {
        'method_id' => 'conversation_supervision_session_create',
        'conversation_id' => conversation.public_id,
        'conversation_supervision_session' => serialize_supervision_session(session)
      }
    end

    def append_conversation_supervision_message!(supervision_session_id:, actor:, content:)
      session = ConversationSupervisionSession.find_by_public_id!(supervision_session_id)
      result = EmbeddedAgents::ConversationSupervision::AppendMessage.call(
        actor: actor,
        conversation_supervision_session: session,
        content: content
      )

      {
        'method_id' => 'conversation_supervision_message_create',
        'conversation_id' => session.target_conversation.public_id,
        'supervision_session_id' => session.public_id,
        'machine_status' => result.fetch('machine_status'),
        'human_sidechat' => result.fetch('human_sidechat'),
        'user_message' => serialize_supervision_message(result.fetch('user_message')),
        'supervisor_message' => serialize_supervision_message(result.fetch('supervisor_message'))
      }
    end

    def app_api_export_conversation!(conversation_id:, agent_connection_credential:, destination_path:, timeout_seconds: 60)
      created = app_api_post_json(
        '/app_api/conversation_export_requests',
        { conversation_id: conversation_id },
        agent_connection_credential:
      )
      request_id = created.dig('export_request', 'request_id')
      shown = wait_for_app_api_request_terminal!(
        path: "/app_api/conversation_export_requests/#{request_id}",
        request_key: 'export_request',
        agent_connection_credential: agent_connection_credential,
        terminal_states: %w[succeeded failed expired],
        timeout_seconds: timeout_seconds
      )
      unless shown.dig('export_request', 'lifecycle_state') == 'succeeded'
        raise "conversation export failed: #{JSON.pretty_generate(shown)}"
      end

      download = app_api_download!(
        "/app_api/conversation_export_requests/#{request_id}/download",
        destination_path: destination_path,
        agent_connection_credential: agent_connection_credential
      )

      {
        'create' => created,
        'show' => shown,
        'download' => download
      }
    end

    def app_api_debug_export_conversation!(conversation_id:, agent_connection_credential:, destination_path:,
                                           timeout_seconds: 60)
      created = app_api_post_json(
        '/app_api/conversation_debug_export_requests',
        { conversation_id: conversation_id },
        agent_connection_credential:
      )
      request_id = created.dig('debug_export_request', 'request_id')
      shown = wait_for_app_api_request_terminal!(
        path: "/app_api/conversation_debug_export_requests/#{request_id}",
        request_key: 'debug_export_request',
        agent_connection_credential: agent_connection_credential,
        terminal_states: %w[succeeded failed expired],
        timeout_seconds: timeout_seconds
      )
      unless shown.dig('debug_export_request', 'lifecycle_state') == 'succeeded'
        raise "conversation debug export failed: #{JSON.pretty_generate(shown)}"
      end

      download = app_api_download!(
        "/app_api/conversation_debug_export_requests/#{request_id}/download",
        destination_path: destination_path,
        agent_connection_credential: agent_connection_credential
      )

      {
        'create' => created,
        'show' => shown,
        'download' => download
      }
    end

    def app_api_import_conversation_bundle!(workspace_id:, zip_path:, agent_connection_credential:, timeout_seconds: 60)
      created = app_api_post_multipart_json(
        '/app_api/conversation_bundle_import_requests',
        params: { workspace_id: workspace_id },
        file_param: :upload_file,
        file_path: zip_path,
        agent_connection_credential: agent_connection_credential
      )
      request_id = created.dig('import_request', 'request_id')
      shown = wait_for_app_api_request_terminal!(
        path: "/app_api/conversation_bundle_import_requests/#{request_id}",
        request_key: 'import_request',
        agent_connection_credential: agent_connection_credential,
        terminal_states: %w[succeeded failed],
        timeout_seconds: timeout_seconds
      )
      unless shown.dig('import_request', 'lifecycle_state') == 'succeeded'
        raise "conversation import failed: #{JSON.pretty_generate(shown)}"
      end

      {
        'create' => created,
        'show' => shown
      }
    end

    def run_fenix_mailbox_pump_once!(agent_connection_credential:, execution_runtime_connection_credential: agent_connection_credential, limit: 10,
                                     inline: true, env: {})
      run_fenix_runtime_task!(
        task_name: 'runtime:mailbox_pump_once',
        agent_connection_credential:,
        execution_runtime_connection_credential:,
        env: {
          'LIMIT' => limit.to_s,
          'INLINE' => inline ? 'true' : 'false'
        }.merge(env)
      )
    end

    def run_fenix_control_loop_once!(agent_connection_credential:, execution_runtime_connection_credential: agent_connection_credential, limit: 10,
                                     inline: true, realtime_timeout_seconds: 5, env: {})
      run_fenix_runtime_task!(
        task_name: 'runtime:control_loop_once',
        agent_connection_credential:,
        execution_runtime_connection_credential:,
        env: {
          'LIMIT' => limit.to_s,
          'INLINE' => inline ? 'true' : 'false',
          'REALTIME_TIMEOUT_SECONDS' => realtime_timeout_seconds.to_s
        }.merge(env)
      )
    end

    def run_fenix_control_loop_for_registration!(registration:, **kwargs)
      run_fenix_control_loop_once!(
        agent_connection_credential: registration.agent_connection_credential,
        execution_runtime_connection_credential: registration.execution_runtime_connection_credential,
        **kwargs
      )
    end

    def run_fenix_runtime_task!(task_name:, agent_connection_credential:, env:, execution_runtime_connection_credential: agent_connection_credential)
      run_runtime_task!(
        project_root: fenix_project_root,
        task_name: task_name,
        env: {
          'CORE_MATRIX_AGENT_CONNECTION_CREDENTIAL' => agent_connection_credential,
          'CORE_MATRIX_EXECUTION_RUNTIME_CONNECTION_CREDENTIAL' => execution_runtime_connection_credential
        }.merge(forwarded_fenix_env).merge(env),
        failure_label: 'fenix mailbox pump'
      )
    end

    def with_fenix_control_worker!(agent_connection_credential:, execution_runtime_connection_credential: agent_connection_credential, limit: 10,
                                   inline: true, realtime_timeout_seconds: 5, env: {})
      worker_pid = nil
      with_runtime_control_worker!(
        project_root: fenix_project_root,
        env: {
          'CORE_MATRIX_AGENT_CONNECTION_CREDENTIAL' => agent_connection_credential,
          'CORE_MATRIX_EXECUTION_RUNTIME_CONNECTION_CREDENTIAL' => execution_runtime_connection_credential,
          'LIMIT' => limit.to_s,
          'INLINE' => inline ? 'true' : 'false',
          'REALTIME_TIMEOUT_SECONDS' => realtime_timeout_seconds.to_s
        }.merge(forwarded_fenix_env).merge(env)
      ) do |pid|
        worker_pid = pid
        yield pid
      end
    ensure
      stop_fenix_control_worker!(worker_pid) if worker_pid.present?
    end

    def with_fenix_control_worker_for_registration!(registration:, **kwargs, &block)
      with_fenix_control_worker!(
        agent_connection_credential: registration.agent_connection_credential,
        execution_runtime_connection_credential: registration.execution_runtime_connection_credential,
        **kwargs,
        &block
      )
    end

    def fenix_project_root
      Pathname.new(ENV.fetch('FENIX_PROJECT_ROOT', Rails.root.join('../agents/fenix').to_s))
    end

    def nexus_project_root
      Pathname.new(ENV.fetch('NEXUS_PROJECT_ROOT', Rails.root.join('../execution_runtimes/nexus').to_s))
    end

    def forwarded_fenix_env
      {}.tap do |env|
        env['FENIX_HOME_ROOT'] = ENV['FENIX_HOME_ROOT'] if ENV['FENIX_HOME_ROOT'].present?
        env['FENIX_STORAGE_ROOT'] = ENV['FENIX_STORAGE_ROOT'] if ENV['FENIX_STORAGE_ROOT'].present?
      end
    end

    def forwarded_nexus_env
      {}.tap do |env|
        env['NEXUS_HOME_ROOT'] = ENV['NEXUS_HOME_ROOT'] if ENV['NEXUS_HOME_ROOT'].present?
        env['NEXUS_STORAGE_ROOT'] = ENV['NEXUS_STORAGE_ROOT'] if ENV['NEXUS_STORAGE_ROOT'].present?
      end
    end

    def run_nexus_runtime_task!(task_name:, execution_runtime_connection_credential:, env: {})
      run_runtime_task!(
        project_root: nexus_project_root,
        task_name: task_name,
        env: {
          'CORE_MATRIX_EXECUTION_RUNTIME_CONNECTION_CREDENTIAL' => execution_runtime_connection_credential
        }.merge(forwarded_nexus_env).merge(env),
        failure_label: 'nexus mailbox pump'
      )
    end

    def run_nexus_mailbox_pump_once!(execution_runtime_connection_credential:, limit: 10, inline: true, env: {})
      run_nexus_runtime_task!(
        task_name: 'runtime:mailbox_pump_once',
        execution_runtime_connection_credential:,
        env: {
          'LIMIT' => limit.to_s,
          'INLINE' => inline ? 'true' : 'false'
        }.merge(env)
      )
    end

    def run_nexus_control_loop_once!(execution_runtime_connection_credential:, limit: 10, inline: true,
                                     realtime_timeout_seconds: 5, env: {})
      run_nexus_runtime_task!(
        task_name: 'runtime:control_loop_once',
        execution_runtime_connection_credential:,
        env: {
          'LIMIT' => limit.to_s,
          'INLINE' => inline ? 'true' : 'false',
          'REALTIME_TIMEOUT_SECONDS' => realtime_timeout_seconds.to_s
        }.merge(env)
      )
    end

    def run_nexus_control_loop_for_registration!(registration:, **kwargs)
      run_nexus_control_loop_once!(
        execution_runtime_connection_credential: registration.execution_runtime_connection_credential,
        **kwargs
      )
    end

    def with_nexus_control_worker!(execution_runtime_connection_credential:, limit: 10, inline: true, realtime_timeout_seconds: 5, env: {})
      worker_pid = nil
      with_runtime_control_worker!(
        project_root: nexus_project_root,
        env: {
          'CORE_MATRIX_EXECUTION_RUNTIME_CONNECTION_CREDENTIAL' => execution_runtime_connection_credential,
          'LIMIT' => limit.to_s,
          'INLINE' => inline ? 'true' : 'false',
          'REALTIME_TIMEOUT_SECONDS' => realtime_timeout_seconds.to_s
        }.merge(forwarded_nexus_env).merge(env)
      ) do |pid|
        worker_pid = pid
        yield pid
      end
    ensure
      stop_nexus_control_worker!(worker_pid) if worker_pid.present?
    end

    def with_nexus_control_worker_for_registration!(registration:, **kwargs, &block)
      with_nexus_control_worker!(
        execution_runtime_connection_credential: registration.execution_runtime_connection_credential,
        **kwargs,
        &block
      )
    end

    def stop_nexus_control_worker!(pid)
      stop_fenix_control_worker!(pid)
    end

    def run_runtime_task!(project_root:, task_name:, env:, failure_label:)
      task_env = {
        'CORE_MATRIX_BASE_URL' => CONTROL_BASE_URL,
        'BUNDLE_GEMFILE' => project_root.join('Gemfile').to_s
      }.merge(env)

      stdout = nil
      stderr = nil
      status = nil

      Bundler.with_unbundled_env do
        stdout, stderr, status = Open3.capture3(
          task_env,
          'bin/rails',
          task_name,
          chdir: project_root.to_s
        )
      end

      raise "#{failure_label} failed: #{stderr.presence || stdout}" unless status.success?

      JSON.parse(stdout)
    end

    def with_runtime_control_worker!(project_root:, env:)
      task_env = {
        'CORE_MATRIX_BASE_URL' => CONTROL_BASE_URL,
        'BUNDLE_GEMFILE' => project_root.join('Gemfile').to_s
      }.merge(env)

      reader, writer = IO.pipe
      pid = nil

      Bundler.with_unbundled_env do
        pid = Process.spawn(
          task_env,
          'bin/rails',
          'runtime:control_loop_forever',
          chdir: project_root.to_s,
          out: writer,
          err: writer
        )
      end

      writer.close
      wait_for_worker_ready!(reader: reader, pid: pid)
      yield pid
    ensure
      reader&.close unless reader.nil? || reader.closed?
    end

    def disconnect_application_record!
      ActiveRecord::Base.connection_handler.clear_all_connections!
    end

    def run_database_reset_command!
      task_env = {
        'RAILS_ENV' => ENV.fetch('RAILS_ENV', 'development'),
        'DISABLE_DATABASE_ENVIRONMENT_CHECK' => '1'
      }
      stdout_chunks = []
      stderr_chunks = []
      commands = [
        ['bin/rails', 'db:drop'],
        ['rm', '-f', 'db/schema.rb'],
        ['bin/rails', 'db:create'],
        ['bin/rails', 'db:migrate'],
        ['bin/rails', 'db:reset']
      ]

      Bundler.with_unbundled_env do
        commands.each do |command|
          stdout, stderr, status = Open3.capture3(
            task_env,
            *command,
            chdir: Rails.root.to_s
          )

          stdout_chunks << "$ #{command.join(' ')}\n#{stdout}".strip if stdout.present?
          stderr_chunks << "$ #{command.join(' ')}\n#{stderr}".strip if stderr.present?

          raise "database reset failed: #{stderr.presence || stdout}" unless status.success?
        end
      end

      { stdout: stdout_chunks.join("\n"), stderr: stderr_chunks.join("\n") }
    end

    def reconnect_application_record!
      ApplicationRecord.establish_connection
      ApplicationRecord.with_connection(&:active?)
    end

    def wait_for_agent_task_terminal!(agent_task_run:, timeout_seconds: 10, poll_interval_seconds: 0.1)
      deadline_at = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout_seconds

      loop do
        reloaded = agent_task_run.reload
        return reloaded if %w[completed failed interrupted canceled].include?(reloaded.lifecycle_state)

        if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline_at
          raise "timed out waiting for agent task run #{agent_task_run.public_id} to finish"
        end

        sleep(poll_interval_seconds)
      end
    end

    def wait_for_process_run!(workflow_node:, timeout_seconds: 10, poll_interval_seconds: 0.1)
      deadline_at = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout_seconds

      loop do
        process_run = ProcessRun.find_by(workflow_node: workflow_node)
        return process_run if process_run.present?

        if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline_at
          raise "timed out waiting for process run for workflow node #{workflow_node.public_id}"
        end

        sleep(poll_interval_seconds)
      end
    end

    def wait_for_workflow_run_terminal!(workflow_run:, timeout_seconds: 15, poll_interval_seconds: 0.1,
                                        inline_if_queued: false, catalog: nil)
      deadline_at = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout_seconds

      loop do
        reloaded = workflow_run.reload
        return reloaded if %w[completed failed canceled].include?(reloaded.lifecycle_state)

        if inline_if_queued
          queued_node = next_inline_workflow_node(reloaded)
          if queued_node.present?
            execute_inline_if_queued!(workflow_node: queued_node, catalog:)
            next
          end
        end

        if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline_at
          raise "timed out waiting for workflow run #{reloaded.public_id} to finish"
        end

        sleep(poll_interval_seconds)
      end
    end

    def wait_for_process_run_state!(process_run:, lifecycle_states:, close_states: nil, timeout_seconds: 10,
                                    poll_interval_seconds: 0.1)
      deadline_at = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout_seconds
      lifecycle_states = Array(lifecycle_states)
      close_states = Array(close_states).compact if close_states.present?

      loop do
        reloaded = process_run.reload
        lifecycle_match = lifecycle_states.include?(reloaded.lifecycle_state)
        close_match = close_states.blank? || close_states.include?(reloaded.close_state)
        return reloaded if lifecycle_match && close_match

        if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline_at
          raise "timed out waiting for process run #{reloaded.public_id} to reach #{lifecycle_states.join(', ')}"
        end

        sleep(poll_interval_seconds)
      end
    end

    def report_results_for(agent_task_run:)
      AgentControlReportReceipt
        .where(agent_task_run:)
        .order(:created_at, :id)
        .pluck(:result_code)
    end

    def mailbox_execution_result_for!(pump_result:, mailbox_item_id:)
      summary = Array(pump_result.fetch('items')).find do |item|
        case item['kind']
        when 'runtime_execution'
          item['mailbox_item_id'] == mailbox_item_id
        when 'mailbox_result'
          item.dig('result', 'mailbox_item_id') == mailbox_item_id
        else
          false
        end
      end

      raise "expected runtime execution summary for mailbox item #{mailbox_item_id}" if summary.blank?

      summary['kind'] == 'mailbox_result' ? summary.fetch('result') : summary
    end

    def create_bring_your_own_agent!(installation:, actor:, key:, display_name:)
      agent = Agent.create!(
        installation: installation,
        key: key,
        display_name: display_name,
        visibility: "public",
        provisioning_origin: "system",
        lifecycle_state: "active"
      )
      onboarding_session = OnboardingSessions::Issue.call(
        installation: installation,
        target_kind: "agent",
        target: agent,
        issued_by: actor,
        expires_at: 2.hours.from_now
      )

      {
        agent: agent,
        onboarding_session: onboarding_session,
        onboarding_token: onboarding_session.plaintext_token
      }
    end

    def register_bring_your_own_runtime!(
      onboarding_token:,
      runtime_base_url:,
      execution_runtime_fingerprint:,
      agent_base_url: runtime_base_url
    )
      onboarding_session = OnboardingSession.find_by_plaintext_token(onboarding_token)
      execution_runtime_registration = register_bring_your_own_execution_runtime!(
        onboarding_token:,
        runtime_base_url: runtime_base_url,
        execution_runtime_fingerprint: execution_runtime_fingerprint
      )
      agent_registration = register_bring_your_own_agent_from_manifest!(
        onboarding_token:,
        agent_base_url: agent_base_url
      )

      RuntimeRegistration.new(
        onboarding_session: onboarding_session,
        onboarding_token: onboarding_token,
        manifest: agent_registration.fetch(:manifest),
        agent: agent_registration.fetch(:agent),
        registration: agent_registration.fetch(:registration).merge(
          'execution_runtime_id' => execution_runtime_registration.fetch(:execution_runtime).public_id,
          'execution_runtime_version_id' => execution_runtime_registration.fetch(:execution_runtime_version)&.public_id,
          'execution_runtime_connection_id' => execution_runtime_registration.fetch(:execution_runtime_connection_id),
          'execution_runtime_fingerprint' => execution_runtime_fingerprint
        ),
        heartbeat: agent_registration.fetch(:heartbeat),
        agent_connection_credential: agent_registration.fetch(:agent_connection_credential),
        execution_runtime_connection_credential: execution_runtime_registration.fetch(:execution_runtime_connection_credential),
        agent_definition_version: agent_registration.fetch(:agent_definition_version),
        execution_runtime: execution_runtime_registration.fetch(:execution_runtime),
        execution_runtime_version: execution_runtime_registration.fetch(:execution_runtime_version)
      )
    end

    def register_bring_your_own_agent_from_manifest!(onboarding_token:, agent_base_url:)
      manifest = live_manifest(base_url: agent_base_url)
      registration = http_post_json(
        "#{CONTROL_BASE_URL}/agent_api/registrations",
        {
          onboarding_token: onboarding_token,
          endpoint_metadata: manifest.fetch('endpoint_metadata'),
          definition_package: manifest.fetch('definition_package')
        }
      )

      agent_connection_credential = registration.fetch('agent_connection_credential')
      heartbeat = http_post_json(
        "#{CONTROL_BASE_URL}/agent_api/heartbeats",
        {
          health_status: 'healthy',
          health_metadata: { 'release' => manifest.fetch('sdk_version') },
          auto_resume_eligible: true
        },
        headers: token_headers(agent_connection_credential)
      )
      agent_definition_version = AgentDefinitionVersion.find_by_public_id!(registration.fetch('agent_definition_version_id'))
      agent_connection = AgentConnection.find_by_public_id!(registration.fetch('agent_connection_id'))
      agent = agent_definition_version.agent

      {
        manifest: manifest,
        registration: registration,
        heartbeat: heartbeat,
        agent: agent,
        agent_connection_credential: agent_connection_credential,
        agent_definition_version: agent_definition_version,
        agent_connection: agent_connection,
        agent_connection_id: registration['agent_connection_id']
      }
    end

    def register_bring_your_own_execution_runtime!(onboarding_token:, runtime_base_url:, execution_runtime_fingerprint:)
      manifest = live_manifest(base_url: runtime_base_url)
      registration = http_post_json(
        "#{CONTROL_BASE_URL}/execution_runtime_api/registrations",
        {
          onboarding_token: onboarding_token,
          endpoint_metadata: manifest.fetch(
            'execution_runtime_connection_metadata',
            default_execution_runtime_connection_metadata(runtime_base_url:)
          ),
          version_package: manifest.fetch('version_package')
        }
      )

      execution_runtime = ExecutionRuntime.find_by_public_id!(registration.fetch('execution_runtime_id'))
      execution_runtime_version = ExecutionRuntimeVersion.find_by_public_id!(registration.fetch('execution_runtime_version_id'))
      execution_runtime_connection =
        ExecutionRuntimeConnection.find_by_public_id!(registration.fetch('execution_runtime_connection_id'))

      {
        manifest: manifest,
        registration: registration,
        execution_runtime: execution_runtime,
        execution_runtime_version: execution_runtime_version,
        execution_runtime_connection: execution_runtime_connection,
        execution_runtime_connection_id: registration['execution_runtime_connection_id'],
        execution_runtime_connection_credential: registration.fetch('execution_runtime_connection_credential')
      }
    end

    def register_bundled_runtime_from_manifest!(
      installation:,
      runtime_base_url:,
      execution_runtime_fingerprint:,
      fingerprint:,
      sdk_version: nil
    )
      manifest = live_manifest(base_url: runtime_base_url)
      resolved_sdk_version = sdk_version || manifest.fetch('sdk_version')
      agent_connection_credential = SecureRandom.hex(32)
      execution_runtime_connection_credential = SecureRandom.hex(32)
      runtime = Installations::RegisterBundledAgentRuntime.call(
        installation: installation,
        agent_connection_credential: agent_connection_credential,
        execution_runtime_connection_credential: execution_runtime_connection_credential,
        configuration: {
          enabled: true,
          agent_key: manifest.fetch('agent_key'),
          display_name: manifest.fetch('display_name'),
          visibility: "public",
          provisioning_origin: "system",
          lifecycle_state: "active",
          execution_runtime_kind: manifest.fetch('execution_runtime_kind', manifest.fetch('execution_runtime_kind', 'local')),
          execution_runtime_fingerprint: execution_runtime_fingerprint,
          execution_runtime_connection_metadata: manifest.fetch(
            'execution_runtime_connection_metadata',
            default_execution_runtime_connection_metadata(runtime_base_url:)
          ),
          endpoint_metadata: manifest.fetch('endpoint_metadata'),
          execution_runtime_capability_payload: manifest.fetch('execution_runtime_capability_payload', {}),
          execution_runtime_tool_catalog: manifest.fetch('execution_runtime_tool_catalog', []),
          fingerprint: fingerprint,
          protocol_version: manifest.fetch('protocol_version'),
          sdk_version: resolved_sdk_version,
          protocol_methods: manifest.fetch('protocol_methods'),
          tool_contract: manifest.fetch('tool_contract'),
          profile_policy: manifest.fetch('profile_policy'),
          canonical_config_schema: manifest.fetch('canonical_config_schema'),
          conversation_override_schema: manifest.fetch('conversation_override_schema'),
          default_canonical_config: manifest.fetch('default_canonical_config')
        }
      )

      RuntimeRegistration.new(
        manifest: manifest,
        runtime: runtime,
        agent_connection_credential: runtime.agent_connection_credential || agent_connection_credential,
        execution_runtime_connection_credential: runtime.execution_runtime_connection_credential || execution_runtime_connection_credential,
        agent_definition_version: runtime.agent_definition_version,
        execution_runtime: runtime.execution_runtime
      )
    end

    def default_execution_runtime_connection_metadata(runtime_base_url:)
      {
        'transport' => 'http',
        'base_url' => runtime_base_url
      }
    end

    def enable_default_workspace!(agent_definition_version:)
      user = User.find_by!(installation: agent_definition_version.installation, role: 'admin')
      user_binding = UserAgentBindings::Enable.call(
        user: user,
        agent: agent_definition_version.agent
      ).binding

      user_binding.workspaces.find_by!(is_default: true)
    end

    def create_conversation!(agent_definition_version:)
      workspace = enable_default_workspace!(agent_definition_version: agent_definition_version)

      {
        actor: workspace.user,
        workspace: workspace,
        conversation: Conversations::CreateRoot.call(
          workspace: workspace,
          agent: agent_definition_version.agent
        )
      }
    end

    def start_turn_workflow_on_conversation!(
      conversation:,
      content:, root_node_key:, root_node_type:, decision_source:,
      execution_runtime: nil,
      selector_source: 'conversation',
      selector: 'candidate:dev/mock-model',
      initial_kind: nil,
      initial_payload: {}
    )
      turn = Turns::StartUserTurn.call(
        conversation: conversation,
        content: content,
        execution_runtime: execution_runtime,
        resolved_config_snapshot: {},
        resolved_model_selection_snapshot: {}
      )
      workflow_run = Workflows::CreateForTurn.call(
        turn: turn,
        root_node_key: root_node_key,
        root_node_type: root_node_type,
        decision_source: decision_source,
        metadata: {},
        selector_source: selector_source,
        selector: selector,
        initial_kind: initial_kind,
        initial_payload: initial_payload
      )

      {
        turn: turn.reload,
        workflow_run: workflow_run.reload,
        agent_task_run: initial_kind.present? ? AgentTaskRun.find_by!(workflow_run: workflow_run).reload : nil
      }
    end

    def execute_provider_workflow!(workflow_run:, timeout_seconds: 3600, catalog: nil, inline_if_queued: true)
      dispatched_node = Workflows::ExecuteRun.call(
        workflow_run: workflow_run
      )
      if inline_if_queued && dispatched_node.present?
        execute_inline_if_queued!(workflow_node: dispatched_node,
                                  catalog: catalog)
      end
      wait_for_workflow_run_terminal!(
        workflow_run:,
        timeout_seconds:,
        inline_if_queued:,
        catalog:
      )
    end

    def execute_provider_turn_on_conversation!(
      conversation:,
      content:, selector:,
      execution_runtime: nil,
      selector_source: 'conversation',
      catalog: nil,
      inline_if_queued: true
    )
      run = start_turn_workflow_on_conversation!(
        conversation: conversation,
        execution_runtime: execution_runtime,
        content: content,
        root_node_key: 'turn_step',
        root_node_type: 'turn_step',
        decision_source: 'system',
        selector_source: selector_source,
        selector: selector
      )
      execute_provider_workflow!(
        workflow_run: run.fetch(:workflow_run),
        catalog: catalog,
        inline_if_queued: inline_if_queued
      )
      run.transform_values { |value| value.respond_to?(:reload) ? value.reload : value }
    end

    def execute_tool_call!(
      workflow_node:,
      tool_call:,
      round_bindings:,
      agent_definition_version:,
      timeout_seconds: 30,
      poll_interval_seconds: 0.1
    )
      deadline_at = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout_seconds

      loop do
        return ProviderExecution::RouteToolCall.call(
          workflow_node: workflow_node,
          tool_call: tool_call,
          round_bindings: round_bindings,
          agent_request_exchange: ProviderExecution::AgentRequestExchange.new(
            agent_definition_version: agent_definition_version
          )
        )
      rescue ProviderExecution::AgentRequestExchange::PendingResponse
        if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline_at
          raise "timed out waiting for agent tool call #{tool_call.fetch('call_id')} to finish"
        end

        sleep(poll_interval_seconds)
      end
    end

    def dispatch_execution_report!(
      agent_definition_version:,
      mailbox_item:,
      agent_task_run:,
      method_id:,
      protocol_message_id:,
      execution_runtime_connection:,
      occurred_at: Time.current,
      **payload
    )
      AgentControl::Poll.call(
        execution_runtime_connection: execution_runtime_connection,
        limit: 10,
        occurred_at: occurred_at
      ) if method_id == 'execution_started'

      AgentControl::Report.call(
        agent_definition_version: agent_definition_version,
        execution_runtime_connection: execution_runtime_connection,
        occurred_at: occurred_at,
        payload: {
          method_id: method_id,
          protocol_message_id: protocol_message_id,
          mailbox_item_id: mailbox_item.public_id,
          agent_task_run_id: agent_task_run.public_id,
          logical_work_id: agent_task_run.logical_work_id,
          attempt_no: agent_task_run.attempt_no,
          **payload
        }
      )
    end

    def run_fenix_mailbox_task!(
      agent_connection_credential:,
      content:,
      mode:,
      agent_definition_version:,
      execution_runtime_connection_credential: agent_connection_credential,
      runtime_base_url: nil,
      extra_payload: {},
      delivery_mode: 'realtime'
    )
      _unused_runtime_base_url = runtime_base_url
      conversation_context = create_conversation!(agent_definition_version: agent_definition_version)
      run = start_turn_workflow_on_conversation!(
        conversation: conversation_context.fetch(:conversation),
        content: content,
        root_node_key: 'agent_turn_step',
        root_node_type: 'turn_step',
        decision_source: 'agent',
        initial_kind: 'turn_step',
        initial_payload: { 'mode' => mode }.merge(extra_payload)
      )
      pump_result =
        if delivery_mode == 'realtime'
          run_fenix_control_loop_once!(
            agent_connection_credential:,
            execution_runtime_connection_credential:
          )
        else
          run_fenix_mailbox_pump_once!(
            agent_connection_credential:,
            execution_runtime_connection_credential:
          )
        end
      agent_task_run = wait_for_agent_task_terminal!(agent_task_run: run.fetch(:agent_task_run))
      mailbox_item = agent_task_run.agent_control_mailbox_items.order(:created_at, :id).last
      raise "expected mailbox item for task run #{agent_task_run.public_id}" if mailbox_item.blank?

      run.merge(
        conversation: conversation_context.fetch(:conversation).reload,
        mailbox_item: mailbox_item,
        execution: mailbox_execution_result_for!(pump_result: pump_result, mailbox_item_id: mailbox_item.public_id),
        report_results: report_results_for(agent_task_run:)
      )
    end

    def workflow_node_keys(workflow_run)
      workflow_run.workflow_nodes.order(:ordinal).pluck(:node_key)
    end

    def workflow_edge_keys(workflow_run)
      workflow_run.workflow_edges
                  .includes(:from_node, :to_node)
                  .sort_by { |edge| [edge.from_node.ordinal, edge.to_node.ordinal] }
                  .map { |edge|                     "#{edge.from_node.node_key}->#{edge.to_node.node_key}" }
    end

    def workflow_state_hash(conversation:, workflow_run:, turn:, agent_task_run: nil, extra: {})
      {
        'conversation_state' => conversation.reload.lifecycle_state,
        'workflow_lifecycle_state' => workflow_run.reload.lifecycle_state,
        'workflow_wait_state' => workflow_run.wait_state,
        'turn_lifecycle_state' => turn.reload.lifecycle_state
      }.tap do |state|
        if agent_task_run.present?
          state['agent_task_run_state'] = agent_task_run.reload.lifecycle_state
          state['selected_output_message_id'] = turn.selected_output_message&.public_id
          state['selected_output_content'] = turn.selected_output_message&.content
        end
        extra.each { |key, value| state[key] = value }
      end
    end

    def scenario_result(scenario:, expected_dag_shape:, observed_dag_shape:, expected_conversation_state:,
                        observed_conversation_state:, proof_artifact_path: nil, extra: {})
      {
        'scenario' => scenario,
        'passed' => expected_dag_shape == observed_dag_shape &&
          expected_conversation_state.all? { |key, value| observed_conversation_state[key] == value },
        'proof_artifact_path' => proof_artifact_path,
        'expected_dag_shape' => expected_dag_shape,
        'observed_dag_shape' => observed_dag_shape,
        'expected_conversation_state' => expected_conversation_state,
        'observed_conversation_state' => observed_conversation_state
      }.merge(extra)
    end

    def write_json(payload, io: $stdout)
      io.puts JSON.pretty_generate(payload)
    end

    def silence_stdout
      original_stdout = $stdout
      $stdout = StringIO.new
      yield
    ensure
      $stdout = original_stdout
    end

    def wait_for_worker_ready!(reader:, pid:, timeout_seconds: 15)
      Timeout.timeout(timeout_seconds) do
        loop do
          line = reader.gets
          raise 'fenix control worker exited before becoming ready' if line.nil? && !process_alive?(pid)
          next if line.blank?

          payload = JSON.parse(line)
          return payload if payload['event'] == 'ready'
        rescue JSON::ParserError
          next
        end
      end
    rescue Timeout::Error
      raise 'timed out waiting for fenix control worker to become ready'
    end

    def stop_fenix_control_worker!(pid)
      return if pid.blank?

      Process.kill('TERM', pid)

      Timeout.timeout(5) do
        Process.wait(pid)
      end
    rescue Errno::ESRCH, Errno::ECHILD
      nil
    rescue Timeout::Error
      begin
        Process.kill('KILL', pid)
        Process.wait(pid)
      rescue Errno::ESRCH, Errno::ECHILD
        nil
      end
    end

    def process_alive?(pid)
      Process.kill(0, pid)
      true
    rescue Errno::ESRCH
      false
    end

    def serialize_supervision_session(session)
      {
        'supervision_session_id' => session.public_id,
        'target_conversation_id' => session.target_conversation.public_id,
        'initiator_type' => session.initiator_type,
        'initiator_id' => session.initiator.respond_to?(:public_id) ? session.initiator.public_id : nil,
        'lifecycle_state' => session.lifecycle_state,
        'responder_strategy' => session.responder_strategy,
        'capability_policy_snapshot' => session.capability_policy_snapshot,
        'last_snapshot_at' => session.last_snapshot_at&.iso8601(6),
        'created_at' => session.created_at&.iso8601(6)
      }.compact
    end

    def serialize_supervision_message(message)
      {
        'supervision_message_id' => message.public_id,
        'supervision_session_id' => message.conversation_supervision_session.public_id,
        'supervision_snapshot_id' => message.conversation_supervision_snapshot.public_id,
        'target_conversation_id' => message.target_conversation.public_id,
        'role' => message.role,
        'content' => message.content,
        'created_at' => message.created_at&.iso8601(6)
      }
    end

    def execute_inline_if_queued!(workflow_node:, catalog: nil)
      current_node = WorkflowNode.find_by(public_id: workflow_node.public_id)
      return if current_node.blank?
      return unless current_node.queued? || current_node.pending?

      Workflows::ExecuteNode.call(
        workflow_node: current_node,
        messages: current_node.workflow_run.execution_snapshot.conversation_projection.fetch('messages').map do |entry|
          entry.slice('role', 'content')
        end,
        catalog: catalog
      )
    end

    def next_inline_workflow_node(workflow_run)
      workflow_run.workflow_nodes
                  .where(lifecycle_state: %w[queued pending])
                  .order(:ordinal, :created_at, :id)
                  .first
    end
  end
end
# rubocop:enable Metrics/ModuleLength, Metrics/MethodLength, Metrics/AbcSize, Metrics/ParameterLists
