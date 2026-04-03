require "json"
require "net/http"
require "uri"

module Fenix
  module Runtime
    class ControlClient
      DEFAULT_OPEN_TIMEOUT = 5
      DEFAULT_READ_TIMEOUT = 30
      DEFAULT_WRITE_TIMEOUT = 30

      def initialize(
        base_url:,
        machine_credential:,
        execution_machine_credential: nil,
        open_timeout: DEFAULT_OPEN_TIMEOUT,
        read_timeout: DEFAULT_READ_TIMEOUT,
        write_timeout: DEFAULT_WRITE_TIMEOUT
      )
        @base_url = base_url
        @machine_credential = machine_credential
        @execution_machine_credential = execution_machine_credential.presence || machine_credential
        @open_timeout = open_timeout
        @read_timeout = read_timeout
        @write_timeout = write_timeout
      end

      def poll(limit:)
        program_items = post_json("/program_api/control/poll", { limit: limit }, credential: machine_credential).fetch("mailbox_items")
        execution_items = post_json("/execution_api/control/poll", { limit: limit }, credential: execution_machine_credential).fetch("mailbox_items")

        (Array(program_items) + Array(execution_items)).map(&:deep_stringify_keys)
      end

      def report!(payload:)
        if execution_report?(payload)
          post_json("/execution_api/control/report", payload, credential: execution_machine_credential)
        else
          post_json("/program_api/control/report", payload, credential: machine_credential)
        end
      end

      def register!(
        enrollment_token:,
        runtime_fingerprint:,
        runtime_kind: "local",
        runtime_connection_metadata:,
        execution_capability_payload: {},
        execution_tool_catalog: [],
        fingerprint:,
        endpoint_metadata:,
        protocol_version:,
        sdk_version:,
        protocol_methods: [],
        tool_catalog: [],
        profile_catalog: {},
        config_schema_snapshot: {},
        conversation_override_schema_snapshot: {},
        default_config_snapshot: {}
      )
        post_json("/program_api/registrations", {
          enrollment_token: enrollment_token,
          runtime_fingerprint: runtime_fingerprint,
          runtime_kind: runtime_kind,
          runtime_connection_metadata: runtime_connection_metadata,
          execution_capability_payload: execution_capability_payload,
          execution_tool_catalog: execution_tool_catalog,
          fingerprint: fingerprint,
          endpoint_metadata: endpoint_metadata,
          protocol_version: protocol_version,
          sdk_version: sdk_version,
          protocol_methods: protocol_methods,
          tool_catalog: tool_catalog,
          profile_catalog: profile_catalog,
          config_schema_snapshot: config_schema_snapshot,
          conversation_override_schema_snapshot: conversation_override_schema_snapshot,
          default_config_snapshot: default_config_snapshot,
        }, authorize: false)
      end

      def heartbeat!(health_status:, auto_resume_eligible:, health_metadata: {}, unavailability_reason: nil)
        post_json("/program_api/heartbeats", {
          health_status: health_status,
          auto_resume_eligible: auto_resume_eligible,
          health_metadata: health_metadata,
          unavailability_reason: unavailability_reason,
        }.compact)
      end

      def health
        get_json("/program_api/health")
      end

      def capabilities_refresh
        get_json("/program_api/capabilities")
      end

      def capabilities_handshake!(
        fingerprint:,
        protocol_version:,
        sdk_version:,
        execution_capability_payload: nil,
        execution_tool_catalog: nil,
        protocol_methods: [],
        tool_catalog: [],
        profile_catalog: {},
        config_schema_snapshot: {},
        conversation_override_schema_snapshot: {},
        default_config_snapshot: {}
      )
        post_json("/program_api/capabilities", {
          fingerprint: fingerprint,
          protocol_version: protocol_version,
          sdk_version: sdk_version,
          execution_capability_payload: execution_capability_payload,
          execution_tool_catalog: execution_tool_catalog,
          protocol_methods: protocol_methods,
          tool_catalog: tool_catalog,
          profile_catalog: profile_catalog,
          config_schema_snapshot: config_schema_snapshot,
          conversation_override_schema_snapshot: conversation_override_schema_snapshot,
          default_config_snapshot: default_config_snapshot,
        }.compact)
      end

      def conversation_transcript_list(conversation_id:, cursor: nil, limit: nil)
        get_json("/program_api/conversation_transcripts", {
          conversation_id: conversation_id,
          cursor: cursor,
          limit: limit,
        }.compact)
      end

      def conversation_variables_get(workspace_id:, conversation_id:, key:)
        get_json("/program_api/conversation_variables/get", {
          workspace_id: workspace_id,
          conversation_id: conversation_id,
          key: key,
        })
      end

      def conversation_variables_mget(workspace_id:, conversation_id:, keys:)
        post_json("/program_api/conversation_variables/mget", {
          workspace_id: workspace_id,
          conversation_id: conversation_id,
          keys: keys,
        })
      end

      def conversation_variables_exists(workspace_id:, conversation_id:, key:)
        get_json("/program_api/conversation_variables/exists", {
          workspace_id: workspace_id,
          conversation_id: conversation_id,
          key: key,
        })
      end

      def conversation_variables_list_keys(workspace_id:, conversation_id:, cursor: nil, limit: nil)
        get_json("/program_api/conversation_variables/list_keys", {
          workspace_id: workspace_id,
          conversation_id: conversation_id,
          cursor: cursor,
          limit: limit,
        }.compact)
      end

      def conversation_variables_resolve(workspace_id:, conversation_id:)
        get_json("/program_api/conversation_variables/resolve", {
          workspace_id: workspace_id,
          conversation_id: conversation_id,
        })
      end

      def conversation_variables_set(workspace_id:, conversation_id:, key:, typed_value_payload:)
        post_json("/program_api/conversation_variables/set", {
          workspace_id: workspace_id,
          conversation_id: conversation_id,
          key: key,
          typed_value_payload: typed_value_payload,
        })
      end

      def conversation_variables_delete(workspace_id:, conversation_id:, key:)
        post_json("/program_api/conversation_variables/delete", {
          workspace_id: workspace_id,
          conversation_id: conversation_id,
          key: key,
        })
      end

      def conversation_variables_promote(workspace_id:, conversation_id:, key:)
        post_json("/program_api/conversation_variables/promote", {
          workspace_id: workspace_id,
          conversation_id: conversation_id,
          key: key,
        })
      end

      def workspace_variables_list(workspace_id:)
        get_json("/program_api/workspace_variables", { workspace_id: workspace_id })
      end

      def workspace_variables_get(workspace_id:, key:)
        get_json("/program_api/workspace_variables/get", {
          workspace_id: workspace_id,
          key: key,
        })
      end

      def workspace_variables_mget(workspace_id:, keys:)
        post_json("/program_api/workspace_variables/mget", {
          workspace_id: workspace_id,
          keys: keys,
        })
      end

      def workspace_variables_write(
        workspace_id:,
        key:,
        typed_value_payload:,
        source_kind:,
        source_turn_id: nil,
        source_workflow_run_id: nil,
        projection_policy: nil
      )
        post_json("/program_api/workspace_variables/write", {
          workspace_id: workspace_id,
          key: key,
          typed_value_payload: typed_value_payload,
          source_kind: source_kind,
          source_turn_id: source_turn_id,
          source_workflow_run_id: source_workflow_run_id,
          projection_policy: projection_policy,
        }.compact)
      end

      def request_human_interaction!(workflow_node_id:, request_type:, blocking: true, request_payload: {})
        post_json("/program_api/human_interactions", {
          workflow_node_id: workflow_node_id,
          request_type: request_type,
          blocking: blocking,
          request_payload: request_payload,
        })
      end

      def create_tool_invocation!(agent_task_run_id:, tool_name:, request_payload:, idempotency_key: nil, stream_output: false, metadata: {})
        post_json("/program_api/tool_invocations", {
          agent_task_run_id: agent_task_run_id,
          tool_name: tool_name,
          request_payload: request_payload,
          idempotency_key: idempotency_key,
          stream_output: stream_output,
          metadata: metadata,
        }.compact)
      end

      def create_command_run!(tool_invocation_id:, command_line:, timeout_seconds: nil, pty: false, metadata: {})
        post_json("/execution_api/command_runs", {
          tool_invocation_id: tool_invocation_id,
          command_line: command_line,
          timeout_seconds: timeout_seconds,
          pty: pty,
          metadata: metadata,
        }.compact, credential: execution_machine_credential)
      end

      def activate_command_run!(command_run_id:)
        post_json("/execution_api/command_runs/#{command_run_id}/activate", {}, credential: execution_machine_credential)
      end

      def create_process_run!(agent_task_run_id:, tool_name:, kind:, command_line:, timeout_seconds: nil, idempotency_key: nil, metadata: {})
        post_json("/execution_api/process_runs", {
          agent_task_run_id: agent_task_run_id,
          tool_name: tool_name,
          kind: kind,
          command_line: command_line,
          timeout_seconds: timeout_seconds,
          idempotency_key: idempotency_key,
          metadata: metadata,
        }.compact, credential: execution_machine_credential)
      end

      def request_attachment!(turn_id:, attachment_id:)
        post_json("/execution_api/attachments/request", {
          turn_id: turn_id,
          attachment_id: attachment_id,
        }, credential: execution_machine_credential)
      end

      private

      attr_reader :machine_credential, :execution_machine_credential

      def get_json(path, params = {}, authorize: true, credential: machine_credential)
        uri = build_uri(path, params)
        request = Net::HTTP::Get.new(uri)
        perform_json_request(uri:, request:, authorize:, credential:)
      end

      def post_json(path, payload, authorize: true, credential: machine_credential)
        uri = build_uri(path)
        request = Net::HTTP::Post.new(uri)
        request["Content-Type"] = "application/json"
        request.body = JSON.generate(payload)
        perform_json_request(uri:, request:, authorize:, credential:)
      end

      def build_uri(path, params = {})
        uri = URI.join(@base_url, path)
        if params.present?
          query = URI.decode_www_form(String(uri.query))
          query.concat(params.map { |key, value| [key.to_s, value] })
          uri.query = URI.encode_www_form(query)
        end
        uri
      end

      def perform_json_request(uri:, request:, authorize:, credential:)
        request["Authorization"] = %(Token token="#{credential}") if authorize && credential.present?

        response = Net::HTTP.start(
          uri.host,
          uri.port,
          use_ssl: uri.scheme == "https",
          open_timeout: @open_timeout,
          read_timeout: @read_timeout,
          write_timeout: @write_timeout
        ) do |http|
          http.request(request)
        end

        body = response.body.to_s
        parsed = body.empty? ? {} : JSON.parse(body)
        raise "HTTP #{response.code}: #{body}" unless response.code.to_i.between?(200, 299)

        parsed
      end

      def execution_report?(payload)
        method_id = payload.fetch("method_id")
        return true if %w[process_started process_output process_exited].include?(method_id)

        %w[resource_close_acknowledged resource_closed resource_close_failed].include?(method_id) &&
          payload["resource_type"] == "ProcessRun"
      end
    end
  end
end
