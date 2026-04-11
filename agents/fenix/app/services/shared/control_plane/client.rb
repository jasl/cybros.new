require "json"
require "net/http"
require "uri"

module Shared
  module ControlPlane
    class Client
      DEFAULT_OPEN_TIMEOUT = 5
      DEFAULT_READ_TIMEOUT = 30
      DEFAULT_WRITE_TIMEOUT = 30

      def initialize(
        base_url:,
        agent_connection_credential:,
        open_timeout: DEFAULT_OPEN_TIMEOUT,
        read_timeout: DEFAULT_READ_TIMEOUT,
        write_timeout: DEFAULT_WRITE_TIMEOUT
      )
        @base_url = base_url
        @agent_connection_credential = agent_connection_credential
        @open_timeout = open_timeout
        @read_timeout = read_timeout
        @write_timeout = write_timeout
      end

      def poll(limit:)
        post_json("/agent_api/control/poll", { limit: limit }, credential: agent_connection_credential)
          .fetch("mailbox_items")
          .map(&:deep_stringify_keys)
      end

      def report!(payload:)
        post_json("/agent_api/control/report", payload, credential: agent_connection_credential)
      end

      def register!(
        enrollment_token:,
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
          "agent_connection_credential" => @agent_connection_credential,
          "open_timeout" => @open_timeout,
          "read_timeout" => @read_timeout,
          "write_timeout" => @write_timeout,
        }
      end

      private

      attr_reader :agent_connection_credential

      def get_json(path, params = {}, authorize: true, credential: agent_connection_credential)
        uri = URI.join(@base_url, path)
        uri.query = URI.encode_www_form(params) if params.present?
        request = Net::HTTP::Get.new(uri)
        perform_json_request(uri: uri, request: request, authorize: authorize, credential: credential)
      end

      def post_json(path, payload, authorize: true, credential: agent_connection_credential)
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
    end
  end
end
