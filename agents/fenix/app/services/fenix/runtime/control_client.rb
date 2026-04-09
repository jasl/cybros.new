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
        program_items = post_json("/agent_api/control/poll", { limit: limit }, credential: machine_credential).fetch("mailbox_items")
        execution_items = post_json("/executor_api/control/poll", { limit: limit }, credential: execution_machine_credential).fetch("mailbox_items")

        (Array(program_items) + Array(execution_items)).map(&:deep_stringify_keys)
      end

      def report!(payload:)
        if execution_report?(payload)
          post_json("/executor_api/control/report", payload, credential: execution_machine_credential)
        else
          post_json("/agent_api/control/report", payload, credential: machine_credential)
        end
      end

      def register!(
        enrollment_token:,
        executor_fingerprint:,
        executor_kind: "local",
        executor_connection_metadata:,
        executor_capability_payload: {},
        executor_tool_catalog: [],
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
          executor_fingerprint: executor_fingerprint,
          executor_kind: executor_kind,
          executor_connection_metadata: executor_connection_metadata,
          executor_capability_payload: executor_capability_payload,
          executor_tool_catalog: executor_tool_catalog,
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
        executor_capability_payload: nil,
        executor_tool_catalog: nil,
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
          executor_capability_payload: executor_capability_payload,
          executor_tool_catalog: executor_tool_catalog,
          protocol_methods: protocol_methods,
          tool_catalog: tool_catalog,
          profile_catalog: profile_catalog,
          config_schema_snapshot: config_schema_snapshot,
          conversation_override_schema_snapshot: conversation_override_schema_snapshot,
          default_config_snapshot: default_config_snapshot,
        }.compact)
      end

      def connection_context
        {
          "base_url" => @base_url,
          "machine_credential" => @machine_credential,
          "execution_machine_credential" => @execution_machine_credential,
          "open_timeout" => @open_timeout,
          "read_timeout" => @read_timeout,
          "write_timeout" => @write_timeout,
        }
      end

      private

      attr_reader :machine_credential, :execution_machine_credential

      def get_json(path, params = {}, authorize: true, credential: machine_credential)
        uri = URI.join(@base_url, path)
        uri.query = URI.encode_www_form(params) if params.present?
        request = Net::HTTP::Get.new(uri)
        perform_json_request(uri: uri, request: request, authorize: authorize, credential: credential)
      end

      def post_json(path, payload, authorize: true, credential: machine_credential)
        uri = URI.join(@base_url, path)
        request = Net::HTTP::Post.new(uri)
        request["Content-Type"] = "application/json"
        request.body = JSON.generate(payload)
        perform_json_request(uri: uri, request: request, authorize: authorize, credential: credential)
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
        return parsed if response.code.to_i == 409 && parsed["result"] == "stale"
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
