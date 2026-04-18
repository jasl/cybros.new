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
require 'zip'
require_relative 'runtime_registration'

raise "Verification::ManualSupport must be loaded via verification/hosted/core_matrix" unless defined?(Rails.application)

# Verification-owned helper surface for operator and scenario validation flows.
# rubocop:disable Metrics/ModuleLength, Metrics/MethodLength, Metrics/AbcSize, Metrics/ParameterLists
module Verification
  # Verification-owned helper surface for operator and scenario validation flows.
  module ManualSupport
    module_function

    CONTROL_BASE_URL = ENV.fetch('CORE_MATRIX_BASE_URL', 'http://127.0.0.1:3000')

    def reset_backend_state!
      return if ActiveModel::Type::Boolean.new.cast(ENV['VERIFICATION_SKIP_BACKEND_RESET'])

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

    def token_headers(bearer_token)
      {
        'Authorization' => ActionController::HttpAuthentication::Token.encode_credentials(bearer_token)
      }
    end

    def execution_runtime_token_headers(bearer_token)
      token_headers(bearer_token)
    end

    def issue_app_api_session_token!(user:, expires_at: 30.days.from_now)
      Session.issue_for!(
        identity: user.identity,
        user: user,
        expires_at: expires_at,
        metadata: { "source" => "verification_app_api" }
      ).plaintext_token
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

    def http_patch_json(url, payload, headers: {})
      uri = URI(url)
      request = Net::HTTP::Patch.new(uri)
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

    def http_download!(url, headers:, destination_path:, max_redirects: 5)
      current_url = url
      current_headers = headers.dup
      redirects_remaining = max_redirects

      loop do
        response, body = http_get_response(current_url, headers: current_headers)
        status_code = response.code.to_i

        if status_code.between?(200, 299)
          FileUtils.mkdir_p(File.dirname(destination_path))
          File.binwrite(destination_path, body)

          return {
            'path' => destination_path.to_s,
            'content_type' => response['Content-Type'],
            'content_disposition' => response['Content-Disposition'],
            'byte_size' => body.bytesize
          }
        end

        if status_code.between?(300, 399)
          raise "HTTP #{response.code}: redirect limit exceeded" if redirects_remaining <= 0

          location = response['Location'].to_s
          raise "HTTP #{response.code}: missing redirect location" if location.empty?

          redirected_url = URI.join(current_url, location).to_s
          current_headers = redirect_follow_headers(current_url:, redirected_url:, headers: current_headers)
          current_url = redirected_url
          redirects_remaining -= 1
          next
        end

        raise "HTTP #{response.code}: #{body}"
      end
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

    def redirect_follow_headers(current_url:, redirected_url:, headers:)
      current_uri = URI(current_url)
      redirected_uri = URI(redirected_url)

      same_origin = current_uri.scheme == redirected_uri.scheme &&
        current_uri.host == redirected_uri.host &&
        current_uri.port == redirected_uri.port

      return headers if same_origin

      headers.except('Authorization')
    end

    def live_manifest(base_url:)
      http_get_json("#{base_url}/runtime/manifest")
    end

    def app_api_get_json(path, session_token:, params: {})
      query = params.present? ? "?#{URI.encode_www_form(params.transform_keys(&:to_s))}" : ''
      http_get_json(control_url(path) + query, headers: token_headers(session_token))
    end

    def app_api_post_json(path, payload, session_token:)
      http_post_json(control_url(path), payload, headers: token_headers(session_token))
    end

    def app_api_patch_json(path, payload, session_token:)
      http_patch_json(control_url(path), payload, headers: token_headers(session_token))
    end

    def app_api_admin_create_onboarding_session!(target_kind:, session_token:, agent_key: nil, display_name: nil)
      app_api_post_json(
        "/app_api/admin/onboarding_sessions",
        {
          target_kind: target_kind,
          agent_key: agent_key,
          display_name: display_name,
        }.compact,
        session_token: session_token
      )
    end

    def app_api_post_multipart_json(path, params:, file_param:, file_path:, session_token:,
                                    content_type: 'application/zip')
      http_post_multipart_json(
        control_url(path),
        params: params,
        file_param: file_param,
        file_path: file_path,
        content_type: content_type,
        headers: token_headers(session_token)
      )
    end

    def execution_runtime_api_post_multipart_json(path, params:, file_param:, file_path:,
                                                  execution_runtime_connection_credential:,
                                                  content_type: 'application/zip')
      http_post_multipart_json(
        control_url(path),
        params: params,
        file_param: file_param,
        file_path: file_path,
        content_type: content_type,
        headers: execution_runtime_token_headers(execution_runtime_connection_credential)
      )
    end

    def app_api_download!(path, destination_path:, session_token:)
      http_download!(
        control_url(path),
        headers: token_headers(session_token),
        destination_path: destination_path
      )
    end

    def wait_for_app_api_request_terminal!(path:, request_key:, session_token:, terminal_states:,
                                           timeout_seconds: 30, poll_interval_seconds: 0.2)
      deadline_at = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout_seconds
      terminal_states = Array(terminal_states)

      loop do
        payload = app_api_get_json(path, session_token:)
        request = payload.fetch(request_key)
        return payload if terminal_states.include?(request.fetch('lifecycle_state'))

        if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline_at
          raise "timed out waiting for app api request #{path} to reach #{terminal_states.join(', ')}"
        end

        sleep(poll_interval_seconds)
      end
    end

    def app_api_conversation_transcript!(conversation_id:, session_token:, cursor: nil, limit: nil)
      app_api_get_json(
        "/app_api/conversations/#{conversation_id}/transcript",
        session_token:,
        params: {
          cursor: cursor,
          limit: limit
        }.compact
      )
    end

    def app_api_conversation_diagnostics_show!(conversation_id:, session_token:)
      app_api_get_json(
        "/app_api/conversations/#{conversation_id}/diagnostics",
        session_token:
      )
    end

    def app_api_conversation_diagnostics_turns!(conversation_id:, session_token:)
      app_api_get_json(
        "/app_api/conversations/#{conversation_id}/diagnostics/turns",
        session_token:
      )
    end

    def wait_for_app_api_conversation_diagnostics_materialized!(
      conversation_id:,
      session_token:,
      timeout_seconds: 30,
      poll_interval_seconds: 0.2
    )
      deadline_at = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout_seconds

      loop do
        conversation_payload = app_api_conversation_diagnostics_show!(
          conversation_id: conversation_id,
          session_token: session_token
        )
        turns_payload = app_api_conversation_diagnostics_turns!(
          conversation_id: conversation_id,
          session_token: session_token
        )

        conversation_ready = %w[ready stale].include?(conversation_payload.fetch("diagnostics_status"))
        turns_ready = %w[ready stale].include?(turns_payload.fetch("diagnostics_status"))

        if conversation_ready && turns_ready
          return {
            "conversation" => conversation_payload,
            "turns" => turns_payload
          }
        end

        if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline_at
          raise "timed out waiting for app api diagnostics for conversation #{conversation_id} to materialize"
        end

        sleep(poll_interval_seconds)
      end
    end

    def app_api_conversation_feed!(conversation_id:, session_token:)
      app_api_get_json(
        "/app_api/conversations/#{conversation_id}/feed",
        session_token:
      )
    end

    def app_api_conversation_turn_runtime_events!(conversation_id:, turn_id:, session_token:)
      app_api_get_json(
        "/app_api/conversations/#{conversation_id}/turns/#{turn_id}/runtime_events",
        session_token:
      )
    end

    def app_api_create_conversation!(workspace_agent_id:, content:, session_token:, selector: nil,
                                     execution_runtime_id: nil)
      app_api_post_json(
        "/app_api/conversations",
        {
          workspace_agent_id: workspace_agent_id,
          content: content,
          selector: selector,
          execution_runtime_id: execution_runtime_id
        }.compact,
        session_token: session_token
      )
    end

    def app_api_conversation_attachment_show!(conversation_id:, attachment_id:, session_token:)
      app_api_get_json(
        "/app_api/conversations/#{conversation_id}/attachments/#{attachment_id}",
        session_token: session_token
      )
    end

    def download_public_url!(url:, destination_path:)
      http_download!(
        url,
        headers: {},
        destination_path: destination_path
      )
    end

    def execution_runtime_publish_output_attachment!(turn_id:, file_path:, execution_runtime_connection_credential:,
                                                     publication_role:, content_type: 'application/zip')
      execution_runtime_api_post_multipart_json(
        "/execution_runtime_api/attachments/publish",
        params: {
          turn_id: turn_id,
          publication_role: publication_role,
        },
        file_param: :file,
        file_path: file_path,
        content_type: content_type,
        execution_runtime_connection_credential: execution_runtime_connection_credential
      )
    end

    def app_api_create_conversation_supervision_session!(conversation_id:, session_token:, responder_strategy: nil)
      app_api_post_json(
        "/app_api/conversations/#{conversation_id}/supervision_sessions",
        {
          responder_strategy: responder_strategy
        }.compact,
        session_token: session_token
      )
    end

    def app_api_append_conversation_supervision_message!(conversation_id:, supervision_session_id:, content:,
                                                         session_token:)
      app_api_post_json(
        "/app_api/conversations/#{conversation_id}/supervision_sessions/#{supervision_session_id}/messages",
        { content: content },
        session_token: session_token
      )
    end

    def app_api_append_conversation_supervision_message_with_retry!(
      conversation_id:,
      supervision_session_id:,
      content:,
      session_token:,
      max_attempts: 2,
      retry_delay_seconds: 1.0
    )
      attempts = []
      request_content = content
      last_response = nil

      max_attempts.times do |attempt_index|
        last_response = app_api_append_conversation_supervision_message!(
          conversation_id: conversation_id,
          supervision_session_id: supervision_session_id,
          content: request_content,
          session_token: session_token
        )

        attempts << {
          "attempt" => attempt_index + 1,
          "request_content" => request_content,
          "response" => last_response,
        }

        unless supervision_refusal_or_apology?(last_response.dig("human_sidechat", "content"))
          return last_response.merge(
            "accepted_attempt" => attempt_index + 1,
            "retry_attempts" => attempts
          )
        end

        break if attempt_index + 1 >= max_attempts

        sleep(retry_delay_seconds) if retry_delay_seconds.positive?
        request_content = supervision_retry_prompt(original_content: content)
      end

      last_response.merge(
        "accepted_attempt" => nil,
        "retry_attempts" => attempts
      )
    end

    def app_api_conversation_supervision_messages!(conversation_id:, supervision_session_id:, session_token:)
      app_api_get_json(
        "/app_api/conversations/#{conversation_id}/supervision_sessions/#{supervision_session_id}/messages",
        session_token: session_token
      )
    end

    def wait_for_app_api_turn_terminal!(conversation_id:, turn_id:, session_token:, terminal_states: %w[completed failed canceled],
                                        timeout_seconds: 3600, poll_interval_seconds: 0.1)
      deadline_at = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout_seconds
      terminal_states = Array(terminal_states)

      loop do
        turns_payload = app_api_conversation_diagnostics_turns!(
          conversation_id: conversation_id,
          session_token: session_token
        )
        turn = turns_payload.fetch('items').find { |candidate| candidate.fetch('turn_id') == turn_id }

        if turn.present? && terminal_states.include?(turn.fetch('lifecycle_state'))
          conversation_payload = app_api_conversation_diagnostics_show!(
            conversation_id: conversation_id,
            session_token: session_token
          )

          return {
            'conversation' => conversation_payload.fetch('snapshot'),
            'turn' => turn,
            'turns' => turns_payload.fetch('items'),
          }
        end

        if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline_at
          raise "timed out waiting for app api turn #{turn_id} to reach #{terminal_states.join(', ')}"
        end

        sleep(poll_interval_seconds)
      end
    end

    def wait_for_app_api_turn_live_activity!(conversation_id:, turn_id:, session_token:,
                                             timeout_seconds: 300, poll_interval_seconds: 0.2,
                                             &readiness_block)
      deadline_at = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout_seconds

      loop do
        turns_payload = app_api_conversation_diagnostics_turns!(
          conversation_id: conversation_id,
          session_token: session_token
        )
        turn = turns_payload.fetch("items").find { |candidate| candidate.fetch("turn_id") == turn_id }

        if turn.present?
          lifecycle_state = turn.fetch("lifecycle_state")
          if lifecycle_state == "active"
            runtime_events = app_api_conversation_turn_runtime_events!(
              conversation_id: conversation_id,
              turn_id: turn_id,
              session_token: session_token
            )
            feed_payload = app_api_conversation_feed!(
              conversation_id: conversation_id,
              session_token: session_token
            )

            ready =
              if readiness_block
                readiness_block.call(turn: turn, runtime_events: runtime_events, feed: feed_payload)
              else
                runtime_activity_present?(runtime_events) || feed_activity_present?(feed_payload)
              end

            if ready
              return {
                "turn" => turn,
                "turns" => turns_payload.fetch("items"),
                "runtime_events" => runtime_events,
                "feed" => feed_payload,
              }
            end
          elsif %w[completed failed canceled].include?(lifecycle_state)
            raise "turn #{turn_id} reached terminal state before live activity was observed"
          end
        end

        if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline_at
          raise "timed out waiting for app api turn #{turn_id} to emit live activity"
        end

        sleep(poll_interval_seconds)
      end
    end

    def wait_for_pending_codex_authorization_session!(installation:, timeout_seconds: 10, poll_interval_seconds: 0.05)
      deadline_at = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout_seconds

      loop do
        session = ApplicationRecord.uncached do
          ProviderAuthorizationSession.where(
            installation: installation,
            provider_handle: "codex_subscription",
            status: "pending"
          ).order(issued_at: :desc, id: :desc).first
        end
        return session if session.present?

        if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline_at
          raise "timed out waiting for pending codex authorization session"
        end

        sleep(poll_interval_seconds)
      end
    end

    def complete_pending_codex_authorization!(installation:, access_token: "verification-codex-access-token",
                                              refresh_token: "verification-codex-refresh-token",
                                              expires_at: 2.hours.from_now)
      authorization_session = ProviderAuthorizationSession.where(
        installation: installation,
        provider_handle: "codex_subscription",
        status: "pending"
      ).order(issued_at: :desc, id: :desc).first || raise("missing pending codex authorization session")

      ProviderCredential.find_or_initialize_by(
        installation: installation,
        provider_handle: "codex_subscription",
        credential_kind: "oauth_codex"
      ).tap do |credential|
        credential.assign_attributes(
          secret: nil,
          access_token: access_token,
          refresh_token: refresh_token,
          expires_at: expires_at,
          last_rotated_at: Time.current,
          last_refreshed_at: nil,
          refresh_failed_at: nil,
          refresh_failure_reason: nil,
          metadata: credential.metadata || {}
        )
        credential.save!
      end

      authorization_session.complete!
      authorization_session
    end

    def turn_live_activity_metrics(turn:, runtime_events:, feed:)
      {
        "provider_round_count" => turn.fetch("provider_round_count", 0).to_i,
        "tool_call_count" => turn.fetch("tool_call_count", 0).to_i,
        "command_run_count" => turn.fetch("command_run_count", 0).to_i,
        "process_run_count" => turn.fetch("process_run_count", 0).to_i,
        "runtime_event_count" => runtime_events.dig("summary", "event_count").to_i,
        "feed_item_count" => Array(feed.fetch("items", [])).length,
      }
    end

    def supervision_refusal_or_apology?(content)
      text = content.to_s
      text.match?(/I.?m sorry/i) || text.match?(/cannot assist/i)
    end

    def supervision_retry_prompt(original_content:)
      <<~TEXT.squish
        Based only on observable progress in this conversation, answer the same supervision request again in one or two short sentences.
        Mention what the 2048 work is doing right now and the latest concrete change if available.
        If a detail is unavailable, say that briefly instead of refusing.
        Original request: #{original_content}
      TEXT
    end

    def wait_for_turn_workflow_terminal!(turn_id:, timeout_seconds: 3600, poll_interval_seconds: 0.1,
                                         inline_if_queued: true, catalog: nil)
      turn = Turn.find_by_public_id!(turn_id)
      workflow_run = turn.workflow_run || raise("workflow run missing for turn #{turn_id}")
      wait_for_workflow_run_terminal!(
        workflow_run: workflow_run,
        timeout_seconds: timeout_seconds,
        poll_interval_seconds: poll_interval_seconds,
        inline_if_queued: inline_if_queued,
        catalog: catalog
      )

      {
        conversation: turn.conversation.reload,
        turn: turn.reload,
        workflow_run: workflow_run.reload
      }
    end

    def create_conversation_supervision_session!(conversation_id:, actor:, responder_strategy: 'hybrid')
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

    def app_api_export_conversation!(conversation_id:, session_token:, destination_path:, timeout_seconds: 60)
      created = app_api_post_json(
        "/app_api/conversations/#{conversation_id}/export_requests",
        {},
        session_token:
      )
      request_id = created.dig('export_request', 'request_id')
      shown = wait_for_app_api_request_terminal!(
        path: "/app_api/conversations/#{conversation_id}/export_requests/#{request_id}",
        request_key: 'export_request',
        session_token: session_token,
        terminal_states: %w[succeeded failed expired],
        timeout_seconds: timeout_seconds
      )
      unless shown.dig('export_request', 'lifecycle_state') == 'succeeded'
        raise "conversation export failed: #{JSON.pretty_generate(shown)}"
      end

      download = app_api_download!(
        "/app_api/conversations/#{conversation_id}/export_requests/#{request_id}/download",
        destination_path: destination_path,
        session_token: session_token
      )

      {
        'create' => created,
        'show' => shown,
        'download' => download
      }
    end

    def app_api_debug_export_conversation!(conversation_id:, session_token:, destination_path:,
                                           timeout_seconds: 60)
      created = app_api_post_json(
        "/app_api/conversations/#{conversation_id}/debug_export_requests",
        {},
        session_token:
      )
      request_id = created.dig('debug_export_request', 'request_id')
      shown = wait_for_app_api_request_terminal!(
        path: "/app_api/conversations/#{conversation_id}/debug_export_requests/#{request_id}",
        request_key: 'debug_export_request',
        session_token: session_token,
        terminal_states: %w[succeeded failed expired],
        timeout_seconds: timeout_seconds
      )
      unless shown.dig('debug_export_request', 'lifecycle_state') == 'succeeded'
        raise "conversation debug export failed: #{JSON.pretty_generate(shown)}"
      end

      download = app_api_download!(
        "/app_api/conversations/#{conversation_id}/debug_export_requests/#{request_id}/download",
        destination_path: destination_path,
        session_token: session_token
      )

      {
        'create' => created,
        'show' => shown,
        'download' => download
      }
    end

    def extract_debug_export_payload!(zip_path)
      entries = {}

      Zip::File.open(zip_path) do |zip_file|
        {
          'manifest' => 'manifest.json',
          'conversation_payload' => 'conversation.json',
          'diagnostics' => 'diagnostics.json',
          'workflow_runs' => 'workflow_runs.json',
          'workflow_nodes' => 'workflow_nodes.json',
          'workflow_edges' => 'workflow_edges.json',
          'workflow_node_events' => 'workflow_node_events.json',
          'workflow_artifacts' => 'workflow_artifacts.json',
          'agent_task_runs' => 'agent_task_runs.json',
          'tool_invocations' => 'tool_invocations.json',
          'command_runs' => 'command_runs.json',
          'process_runs' => 'process_runs.json',
          'subagent_connections' => 'subagent_connections.json',
          'conversation_supervision_sessions' => 'conversation_supervision_sessions.json',
          'conversation_supervision_messages' => 'conversation_supervision_messages.json',
          'usage_events' => 'usage_events.json',
        }.each do |payload_key, entry_name|
          entry = zip_file.find_entry(entry_name)
          next if entry.blank?

          entries[payload_key] = JSON.parse(entry.get_input_stream.read)
        end
      end

      entries
    end

    def runtime_activity_present?(runtime_events_payload)
      return false if runtime_events_payload.blank?

      runtime_events_payload.dig("summary", "event_count").to_i.positive? ||
        Array(runtime_events_payload["segments"]).any? { |segment| Array(segment["events"]).any? }
    end

    def feed_activity_present?(feed_payload)
      Array(feed_payload&.fetch("items", [])).any?
    end

    def app_api_import_conversation_bundle!(workspace_id:, zip_path:, session_token:, timeout_seconds: 60)
      created = app_api_post_multipart_json(
        "/app_api/workspaces/#{workspace_id}/conversation_bundle_import_requests",
        params: {},
        file_param: :upload_file,
        file_path: zip_path,
        session_token: session_token
      )
      request_id = created.dig('import_request', 'request_id')
      shown = wait_for_app_api_request_terminal!(
        path: "/app_api/workspaces/#{workspace_id}/conversation_bundle_import_requests/#{request_id}",
        request_key: 'import_request',
        session_token: session_token,
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
                                   inline: true, realtime_timeout_seconds: 5, ready_timeout_seconds: 30, env: {})
      worker_pid = nil
      with_runtime_control_worker!(
        project_root: fenix_project_root,
        worker_label: 'fenix control worker',
        ready_timeout_seconds: ready_timeout_seconds,
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

    def with_nexus_control_worker!(execution_runtime_connection_credential:, limit: 10, inline: true,
                                   realtime_timeout_seconds: 5, ready_timeout_seconds: 30, env: {},
                                   runtime_base_url: default_nexus_runtime_base_url)
      _unused_limit = limit
      _unused_inline = inline
      _unused_realtime_timeout_seconds = realtime_timeout_seconds
      worker_pid = nil
      nexus_env = forwarded_nexus_env.merge(env)
      nexus_env['NEXUS_HOME_ROOT'] ||= default_nexus_home_root.to_s
      project_root = nexus_project_root
      task_env = {
        'CORE_MATRIX_BASE_URL' => CONTROL_BASE_URL,
        'CORE_MATRIX_EXECUTION_RUNTIME_CONNECTION_CREDENTIAL' => execution_runtime_connection_credential,
        'BUNDLE_GEMFILE' => project_root.join('Gemfile').to_s
      }.merge(nexus_env)
      task_env = apply_nexus_runtime_http_env(task_env, runtime_base_url: runtime_base_url)
      runtime_port = Integer(task_env.fetch('NEXUS_HTTP_PORT'))

      stop_listener_on_port!(runtime_port)

      reader, writer = IO.pipe

      Bundler.with_unbundled_env do
        worker_pid = Process.spawn(
          task_env,
          'bundle', 'exec', './exe/nexus', 'run',
          chdir: project_root.to_s,
          out: writer,
          err: writer
        )
      end

      writer.close
      wait_for_nexus_runtime_ready!(
        base_url: task_env.fetch('NEXUS_PUBLIC_BASE_URL'),
        home_root: task_env.fetch('NEXUS_HOME_ROOT'),
        reader: reader,
        pid: worker_pid,
        timeout_seconds: ready_timeout_seconds,
        worker_label: 'nexus control worker'
      )
      yield worker_pid
    ensure
      writer&.close unless writer.nil? || writer.closed?
      reader&.close unless reader.nil? || reader.closed?
      stop_nexus_control_worker!(worker_pid) if worker_pid.present?
    end

    def with_nexus_control_worker_for_registration!(registration:, **kwargs, &block)
      with_nexus_control_worker!(
        execution_runtime_connection_credential: registration.execution_runtime_connection_credential,
        runtime_base_url: registration.respond_to?(:runtime_base_url) ? registration.runtime_base_url : default_nexus_runtime_base_url,
        **kwargs,
        &block
      )
    end

    def stop_nexus_control_worker!(pid)
      stop_fenix_control_worker!(pid)
    end

    def default_nexus_runtime_base_url
      ENV.fetch('NEXUS_RUNTIME_BASE_URL', 'http://127.0.0.1:3301')
    end

    def default_nexus_home_root
      Verification.repo_root.join('tmp', 'verification-nexus-home')
    end

    def apply_nexus_runtime_http_env(env, runtime_base_url:)
      runtime_uri = URI.parse(runtime_base_url)
      runtime_port = runtime_uri.port || (runtime_uri.scheme == 'https' ? 443 : 80)
      normalized_env = env.dup

      normalized_env['NEXUS_PUBLIC_BASE_URL'] = runtime_base_url
      normalized_env['NEXUS_HTTP_BIND'] = runtime_uri.host
      normalized_env['NEXUS_HTTP_PORT'] = runtime_port.to_s
      normalized_env
    end

    def stop_listener_on_port!(port)
      pids = `lsof -nP -iTCP:#{port} -sTCP:LISTEN -t 2>/dev/null`.lines.map(&:strip).reject(&:blank?).map(&:to_i)
      return if pids.empty?

      pids.each do |pid|
        Process.kill('TERM', pid)
      rescue Errno::ESRCH
        nil
      end

      Timeout.timeout(5) do
        loop do
          live_pids = pids.select { |pid| process_alive?(pid) }
          break if live_pids.empty?

          sleep(0.1)
        end
      end
    rescue Timeout::Error
      pids.each do |pid|
        Process.kill('KILL', pid)
      rescue Errno::ESRCH
        nil
      end
    end

    def wait_for_nexus_runtime_ready!(base_url:, home_root:, reader:, pid:, timeout_seconds: 15, worker_label: 'nexus control worker')
      deadline_at = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout_seconds
      buffered_output = +""
      recent_output = []

      loop do
        record_recent_worker_output!(reader: reader, buffered_output: buffered_output, recent_output: recent_output)
        return if nexus_runtime_ready?(base_url) && nexus_runtime_state_ready?(home_root)

        raise worker_ready_timeout_message(worker_label, recent_output) if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline_at
        raise "#{worker_label} exited before becoming ready#{worker_output_excerpt(recent_output)}" unless process_alive?(pid)

        IO.select([reader], nil, nil, 0.1)
      end
    end

    def nexus_runtime_ready?(base_url)
      response = Net::HTTP.get_response(URI.join(base_url, '/health/ready'))
      response.code == '200'
    rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, EOFError, Net::HTTPError, SocketError
      false
    end

    def nexus_runtime_state_ready?(home_root)
      state_path = File.join(home_root, 'state.sqlite3')

      File.size?(state_path).present? &&
        %w[memory skills logs tmp].all? { |entry| File.directory?(File.join(home_root, entry)) }
    end

    def record_recent_worker_output!(reader:, buffered_output:, recent_output:)
      loop do
        chunk = reader.read_nonblock(4096, exception: false)
        case chunk
        when :wait_readable, nil
          break
        else
          buffered_output << chunk
        end
      end

      while (newline_index = buffered_output.index("\n"))
        line = buffered_output.slice!(0..newline_index).strip
        next if line.empty?

        recent_output << line
        recent_output.shift while recent_output.length > 10
      end
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

    def with_runtime_control_worker!(project_root:, env:, worker_label:, ready_timeout_seconds: 30)
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
      wait_for_worker_ready!(
        reader: reader,
        pid: pid,
        timeout_seconds: ready_timeout_seconds,
        worker_label: worker_label
      )
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
      session_token = issue_app_api_session_token!(user: actor)
      created = app_api_admin_create_onboarding_session!(
        target_kind: "agent",
        agent_key: key,
        display_name: display_name,
        session_token: session_token
      )
      onboarding_session = OnboardingSession.find_by_public_id!(
        created.dig("onboarding_session", "onboarding_session_id")
      )
      agent = Agent.find_by_public_id!(created.dig("onboarding_session", "target_agent_id"))

      {
        agent: agent,
        onboarding_session: onboarding_session,
        onboarding_token: created.fetch("onboarding_token")
      }
    end

    def create_bring_your_own_execution_runtime!(installation:, actor:)
      session_token = issue_app_api_session_token!(user: actor)
      created = app_api_admin_create_onboarding_session!(
        target_kind: "execution_runtime",
        session_token: session_token
      )
      onboarding_session = OnboardingSession.find_by_public_id!(
        created.dig("onboarding_session", "onboarding_session_id")
      )

      {
        onboarding_session: onboarding_session,
        onboarding_token: created.fetch("onboarding_token")
      }
    end

    def register_bring_your_own_runtime!(
      onboarding_token:,
      runtime_base_url:,
      execution_runtime_fingerprint:,
      agent_base_url: runtime_base_url
    )
      onboarding_session = OnboardingSession.find_by_plaintext_token(onboarding_token)
      admin_session_token = issue_app_api_session_token!(user: onboarding_session.issued_by_user)
      runtime_onboarding = app_api_admin_create_onboarding_session!(
        target_kind: "execution_runtime",
        session_token: admin_session_token
      )
      execution_runtime_registration = register_bring_your_own_execution_runtime!(
        onboarding_token: runtime_onboarding.fetch("onboarding_token"),
        runtime_base_url: runtime_base_url,
        execution_runtime_fingerprint: execution_runtime_fingerprint
      )
      onboarding_session.target_agent&.update!(
        default_execution_runtime: execution_runtime_registration.fetch(:execution_runtime)
      )
      agent_registration = register_bring_your_own_agent_from_manifest!(
        onboarding_token: onboarding_token,
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
        "#{CONTROL_BASE_URL}/execution_runtime_api/session/open",
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
          canonical_config_schema: manifest.fetch('canonical_config_schema'),
          conversation_override_schema: manifest.fetch('conversation_override_schema'),
          workspace_agent_settings_schema: manifest.fetch('workspace_agent_settings_schema', {}),
          default_workspace_agent_settings: manifest.fetch('default_workspace_agent_settings', {}),
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
      workspace = Workspaces::MaterializeDefault.call(user: user, agent: agent_definition_version.agent)
      workspace_agent = workspace.workspace_agents.where(agent: agent_definition_version.agent, lifecycle_state: 'active').order(:id).first

      {
        workspace: workspace,
        workspace_agent: workspace_agent,
      }
    end

    def create_conversation!(agent_definition_version:)
      workspace_context = enable_default_workspace!(agent_definition_version: agent_definition_version)
      workspace = workspace_context.fetch(:workspace)
      workspace_agent = workspace_context.fetch(:workspace_agent)

      {
        actor: workspace.user,
        workspace: workspace,
        workspace_agent: workspace_agent,
        conversation: Conversations::CreateRoot.call(
          workspace_agent: workspace_agent
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

    def wait_for_worker_ready!(reader:, pid:, timeout_seconds: 15, worker_label: 'fenix control worker')
      deadline_at = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout_seconds
      buffered_output = +""
      recent_output = []

      loop do
        remaining = deadline_at - Process.clock_gettime(Process::CLOCK_MONOTONIC)
        flush_worker_output_buffer!(buffered_output, recent_output)
        raise worker_ready_timeout_message(worker_label, recent_output) if remaining <= 0

        readable, = IO.select([reader], nil, nil, remaining)
        flush_worker_output_buffer!(buffered_output, recent_output)
        raise worker_ready_timeout_message(worker_label, recent_output) if readable.nil?

        chunk = reader.read_nonblock(4096, exception: false)
        case chunk
        when :wait_readable
          next
        when nil
          flush_worker_output_buffer!(buffered_output, recent_output)
          raise "#{worker_label} exited before becoming ready#{worker_output_excerpt(recent_output)}" unless process_alive?(pid)

          next
        else
          buffered_output << chunk
          payload = flush_worker_output_buffer!(buffered_output, recent_output)
          return payload if payload.present?
        end
      end
    end

    def flush_worker_output_buffer!(buffered_output, recent_output)
      ready_payload = nil

      while (newline_index = buffered_output.index("\n"))
        line = buffered_output.slice!(0..newline_index).strip
        next if line.empty?

        recent_output << line
        recent_output.shift while recent_output.length > 10

        payload = parse_worker_ready_payload(line)
        ready_payload = payload if payload&.fetch('event', nil) == 'ready'
      end

      ready_payload
    end

    def parse_worker_ready_payload(line)
      JSON.parse(line)
    rescue JSON::ParserError
      json_start = line.index('{')
      return nil if json_start.nil?

      JSON.parse(line[json_start..])
    rescue JSON::ParserError
      nil
    end

    def worker_ready_timeout_message(worker_label, recent_output)
      "timed out waiting for #{worker_label} to become ready#{worker_output_excerpt(recent_output)}"
    end

    def worker_output_excerpt(recent_output)
      return '' if recent_output.empty?

      " (recent output: #{recent_output.join(' | ')})"
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
