require "json"
require "net/http"
require "time"
require "uri"

module CybrosNexus
  module Session
    class Client
      SESSION_OPEN_PATH = "/execution_runtime_api/session/open".freeze
      SESSION_REFRESH_PATH = "/execution_runtime_api/session/refresh".freeze
      DEFAULT_MAILBOX_PULL_PATH = "/execution_runtime_api/mailbox/pull".freeze
      DEFAULT_EVENTS_BATCH_PATH = "/execution_runtime_api/events/batch".freeze

      def initialize(base_url:, store:, connection_credential: nil, http_transport: nil)
        @base_url = base_url
        @store = store
        @connection_credential = connection_credential
        @http_transport = http_transport
        @transport_hints = nil
      end

      def open_or_resume(onboarding_token:, endpoint_metadata:, version_package:)
        if present_string?(connection_credential)
          refresh_session(version_package: version_package)
        else
          raise ArgumentError, "missing onboarding token for runtime session open" unless present_string?(onboarding_token)

          open_session(
            onboarding_token: onboarding_token,
            endpoint_metadata: endpoint_metadata,
            version_package: version_package
          )
        end
      end

      def open_session(onboarding_token:, endpoint_metadata:, version_package:)
        persist_session(
          request_json(
            :post,
            SESSION_OPEN_PATH,
            json: {
              "onboarding_token" => onboarding_token,
              "endpoint_metadata" => endpoint_metadata,
              "version_package" => version_package,
            }
          )
        )
      end

      def refresh_session(version_package: nil)
        payload = {}
        payload["version_package"] = version_package if version_package

        persist_session(
          request_json(
            :post,
            SESSION_REFRESH_PATH,
            json: payload,
            credential: fetch_connection_credential!
          )
        )
      end

      def pull_mailbox(limit:)
        request_json(
          :post,
          transport_hints.dig("mailbox", "pull_path") || DEFAULT_MAILBOX_PULL_PATH,
          json: { "limit" => limit },
          credential: fetch_connection_credential!
        )
      end

      def submit_events(events:)
        normalized_events = Array(events)
        return { "method_id" => "execution_runtime_events_batch", "results" => [] } if normalized_events.empty?

        request_json(
          :post,
          transport_hints.dig("events", "batch_path") || DEFAULT_EVENTS_BATCH_PATH,
          json: { "events" => normalized_events },
          credential: fetch_connection_credential!
        )
      end

      def connection_credential
        @connection_credential ||= persisted_session&.fetch(:credential)
      end

      def transport_hints
        @transport_hints ||= persisted_session&.fetch(:transport_hints) || {}
      end

      private

      attr_reader :store

      def fetch_connection_credential!
        connection_credential || raise(ArgumentError, "missing execution runtime connection credential")
      end

      def request_json(method, path, json:, credential: nil)
        headers = {
          "Accept" => "application/json",
          "Content-Type" => "application/json",
        }
        headers["Authorization"] = %(Token token="#{credential}") if present_string?(credential)

        response =
          if @http_transport
            @http_transport.call(method: method, path: path, headers: headers, json: json)
          else
            perform_net_http_request(method: method, path: path, headers: headers, json: json)
          end

        status = response[:status] || response["status"]
        body = normalize_body(response[:body] || response["body"] || {})
        raise CybrosNexus::Error, "request to #{path} failed with status #{status}" unless status.to_i.between?(200, 299)

        body
      end

      def perform_net_http_request(method:, path:, headers:, json:)
        uri = URI.join(@base_url, path)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"

        request = request_class_for(method).new(uri)
        headers.each { |name, value| request[name] = value }
        request.body = JSON.generate(json)

        response = http.request(request)

        {
          status: response.code.to_i,
          body: response.body.to_s.empty? ? {} : JSON.parse(response.body),
        }
      end

      def request_class_for(method)
        case method
        when :post
          Net::HTTP::Post
        when :get
          Net::HTTP::Get
        else
          raise ArgumentError, "unsupported request method #{method.inspect}"
        end
      end

      def persist_session(payload)
        connection_id = payload.fetch("execution_runtime_connection_id")
        credential = payload["execution_runtime_connection_credential"] || fetch_connection_credential!
        now = Time.now.utc.iso8601
        transport_hint_json = JSON.generate(payload["transport_hints"] || {})

        store.database.execute(
          <<~SQL,
            INSERT INTO runtime_sessions (
              session_id,
              credential,
              version_fingerprint,
              transport_hint,
              last_refresh_at,
              created_at
            )
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(session_id) DO UPDATE SET
              credential = excluded.credential,
              version_fingerprint = excluded.version_fingerprint,
              transport_hint = excluded.transport_hint,
              last_refresh_at = excluded.last_refresh_at
          SQL
          [
            connection_id,
            credential,
            payload["execution_runtime_fingerprint"],
            transport_hint_json,
            now,
            now,
          ]
        )

        @connection_credential = credential
        @transport_hints = normalize_body(payload["transport_hints"] || {})
        payload
      end

      def persisted_session
        row = store.database.get_first_row(
          <<~SQL
            SELECT session_id, credential, version_fingerprint, transport_hint, last_refresh_at, created_at
            FROM runtime_sessions
            ORDER BY created_at DESC, session_id DESC
            LIMIT 1
          SQL
        )
        return unless row

        {
          session_id: row[0],
          credential: row[1],
          version_fingerprint: row[2],
          transport_hints: normalize_body(row[3] || "{}"),
          last_refresh_at: row[4],
          created_at: row[5],
        }
      end

      def normalize_body(body)
        return JSON.parse(body) if body.is_a?(String)

        JSON.parse(JSON.generate(body))
      rescue JSON::ParserError
        body
      end

      def present_string?(value)
        value.is_a?(String) ? !value.empty? : !value.nil?
      end
    end
  end
end
