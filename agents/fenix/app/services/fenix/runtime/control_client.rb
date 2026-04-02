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
        open_timeout: DEFAULT_OPEN_TIMEOUT,
        read_timeout: DEFAULT_READ_TIMEOUT,
        write_timeout: DEFAULT_WRITE_TIMEOUT
      )
        @base_url = base_url
        @machine_credential = machine_credential
        @open_timeout = open_timeout
        @read_timeout = read_timeout
        @write_timeout = write_timeout
      end

      def poll(limit:)
        post_json("/agent_api/control/poll", { limit: limit }).fetch("mailbox_items")
      end

      def report!(payload:)
        post_json("/agent_api/control/report", payload)
      end

      def register!(
        enrollment_token:,
        environment_fingerprint:,
        environment_kind: "local",
        environment_connection_metadata:,
        environment_capability_payload: {},
        environment_tool_catalog: [],
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
        post_json("/agent_api/registrations", {
          enrollment_token: enrollment_token,
          environment_fingerprint: environment_fingerprint,
          environment_kind: environment_kind,
          environment_connection_metadata: environment_connection_metadata,
          environment_capability_payload: environment_capability_payload,
          environment_tool_catalog: environment_tool_catalog,
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
        post_json("/agent_api/heartbeats", {
          health_status: health_status,
          auto_resume_eligible: auto_resume_eligible,
          health_metadata: health_metadata,
          unavailability_reason: unavailability_reason,
        }.compact)
      end

      def health
        get_json("/agent_api/health")
      end

      def capabilities_refresh
        get_json("/agent_api/capabilities")
      end

      def capabilities_handshake!(
        fingerprint:,
        protocol_version:,
        sdk_version:,
        environment_capability_payload: nil,
        environment_tool_catalog: nil,
        protocol_methods: [],
        tool_catalog: [],
        profile_catalog: {},
        config_schema_snapshot: {},
        conversation_override_schema_snapshot: {},
        default_config_snapshot: {}
      )
        post_json("/agent_api/capabilities", {
          fingerprint: fingerprint,
          protocol_version: protocol_version,
          sdk_version: sdk_version,
          environment_capability_payload: environment_capability_payload,
          environment_tool_catalog: environment_tool_catalog,
          protocol_methods: protocol_methods,
          tool_catalog: tool_catalog,
          profile_catalog: profile_catalog,
          config_schema_snapshot: config_schema_snapshot,
          conversation_override_schema_snapshot: conversation_override_schema_snapshot,
          default_config_snapshot: default_config_snapshot,
        }.compact)
      end

      def conversation_transcript_list(conversation_id:, cursor: nil, limit: nil)
        get_json("/agent_api/conversation_transcripts", {
          conversation_id: conversation_id,
          cursor: cursor,
          limit: limit,
        }.compact)
      end

      def conversation_variables_get(workspace_id:, conversation_id:, key:)
        get_json("/agent_api/conversation_variables/get", {
          workspace_id: workspace_id,
          conversation_id: conversation_id,
          key: key,
        })
      end

      def conversation_variables_mget(workspace_id:, conversation_id:, keys:)
        post_json("/agent_api/conversation_variables/mget", {
          workspace_id: workspace_id,
          conversation_id: conversation_id,
          keys: keys,
        })
      end

      def conversation_variables_exists(workspace_id:, conversation_id:, key:)
        get_json("/agent_api/conversation_variables/exists", {
          workspace_id: workspace_id,
          conversation_id: conversation_id,
          key: key,
        })
      end

      def conversation_variables_list_keys(workspace_id:, conversation_id:, cursor: nil, limit: nil)
        get_json("/agent_api/conversation_variables/list_keys", {
          workspace_id: workspace_id,
          conversation_id: conversation_id,
          cursor: cursor,
          limit: limit,
        }.compact)
      end

      def conversation_variables_resolve(workspace_id:, conversation_id:)
        get_json("/agent_api/conversation_variables/resolve", {
          workspace_id: workspace_id,
          conversation_id: conversation_id,
        })
      end

      def conversation_variables_set(workspace_id:, conversation_id:, key:, typed_value_payload:)
        post_json("/agent_api/conversation_variables/set", {
          workspace_id: workspace_id,
          conversation_id: conversation_id,
          key: key,
          typed_value_payload: typed_value_payload,
        })
      end

      def conversation_variables_delete(workspace_id:, conversation_id:, key:)
        post_json("/agent_api/conversation_variables/delete", {
          workspace_id: workspace_id,
          conversation_id: conversation_id,
          key: key,
        })
      end

      def conversation_variables_promote(workspace_id:, conversation_id:, key:)
        post_json("/agent_api/conversation_variables/promote", {
          workspace_id: workspace_id,
          conversation_id: conversation_id,
          key: key,
        })
      end

      def workspace_variables_list(workspace_id:)
        get_json("/agent_api/workspace_variables", { workspace_id: workspace_id })
      end

      def workspace_variables_get(workspace_id:, key:)
        get_json("/agent_api/workspace_variables/get", {
          workspace_id: workspace_id,
          key: key,
        })
      end

      def workspace_variables_mget(workspace_id:, keys:)
        post_json("/agent_api/workspace_variables/mget", {
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
        post_json("/agent_api/workspace_variables/write", {
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
        post_json("/agent_api/human_interactions", {
          workflow_node_id: workflow_node_id,
          request_type: request_type,
          blocking: blocking,
          request_payload: request_payload,
        })
      end

      def create_tool_invocation!(agent_task_run_id:, tool_name:, request_payload:, idempotency_key: nil, stream_output: false, metadata: {})
        post_json("/agent_api/tool_invocations", {
          agent_task_run_id: agent_task_run_id,
          tool_name: tool_name,
          request_payload: request_payload,
          idempotency_key: idempotency_key,
          stream_output: stream_output,
          metadata: metadata,
        }.compact)
      end

      def create_command_run!(tool_invocation_id:, command_line:, timeout_seconds: nil, pty: false, metadata: {})
        post_json("/agent_api/command_runs", {
          tool_invocation_id: tool_invocation_id,
          command_line: command_line,
          timeout_seconds: timeout_seconds,
          pty: pty,
          metadata: metadata,
        }.compact)
      end

      def activate_command_run!(command_run_id:)
        post_json("/agent_api/command_runs/#{command_run_id}/activate", {})
      end

      def create_process_run!(agent_task_run_id:, tool_name:, kind:, command_line:, timeout_seconds: nil, idempotency_key: nil, metadata: {})
        post_json("/agent_api/process_runs", {
          agent_task_run_id: agent_task_run_id,
          tool_name: tool_name,
          kind: kind,
          command_line: command_line,
          timeout_seconds: timeout_seconds,
          idempotency_key: idempotency_key,
          metadata: metadata,
        }.compact)
      end

      private

      def get_json(path, params = {}, authorize: true)
        uri = build_uri(path, params)
        request = Net::HTTP::Get.new(uri)
        perform_json_request(uri:, request:, authorize:)
      end

      def post_json(path, payload, authorize: true)
        uri = build_uri(path)
        request = Net::HTTP::Post.new(uri)
        request["Content-Type"] = "application/json"
        request.body = JSON.generate(payload)
        perform_json_request(uri:, request:, authorize:)
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

      def perform_json_request(uri:, request:, authorize:)
        request["Authorization"] = %(Token token="#{@machine_credential}") if authorize && @machine_credential.present?

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
    end
  end
end
