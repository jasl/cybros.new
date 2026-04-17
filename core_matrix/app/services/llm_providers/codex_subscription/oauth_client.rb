require "json"
require "net/http"
require "time"
require "uri"

module LLMProviders
  module CodexSubscription
    class OAuthClient
      DEFAULT_ISSUER_BASE_URL = "https://auth.openai.com".freeze
      DEFAULT_CLIENT_ID = "app_EMoamEEZ73f0CkXaXp7hrann".freeze
      DEVICE_AUTH_CALLBACK_PATH = "/deviceauth/callback".freeze
      DEVICE_AUTH_USER_CODE_PATH = "/api/accounts/deviceauth/usercode".freeze
      DEVICE_AUTH_TOKEN_PATH = "/api/accounts/deviceauth/token".freeze
      VERIFICATION_PATH = "/codex/device".freeze
      DEFAULT_SCOPES = [
        "openid",
        "profile",
        "email",
        "offline_access",
        "api.connectors.read",
        "api.connectors.invoke",
      ].freeze

      class RequestFailed < StandardError
        attr_reader :status, :response_body, :error_code

        def initialize(message, status:, response_body:, error_code: nil)
          super(message)
          @status = status
          @response_body = response_body
          @error_code = error_code
        end

        def client_error?
          status.to_i >= 400 && status.to_i < 500
        end
      end

      def self.refresh_tokens(refresh_token:, issuer_base_url: default_issuer_base_url, client_id: default_client_id)
        _status, body = post_form(
          uri: oauth_token_uri(issuer_base_url),
          form_data: {
            grant_type: "refresh_token",
            refresh_token: refresh_token,
            client_id: client_id,
          },
          allow_oauth_error: true
        )

        if (error_code = oauth_error_code(body))
          raise RequestFailed.new(
            "oauth token request failed",
            status: 400,
            response_body: body,
            error_code: error_code
          )
        end

        {
          access_token: body.fetch("access_token"),
          refresh_token: body["refresh_token"],
          expires_at: Time.current + body.fetch("expires_in").to_i.seconds,
        }
      rescue RequestFailed => error
        raise error unless permanent_refresh_failure?(error.response_body)

        raise ProviderCredentials::RefreshOAuthCredential::PermanentRefreshFailure.new(
          reason: refresh_failure_reason(error.response_body, fallback: error.error_code),
          message: error.message
        )
      end

      def self.start_device_flow!(issuer_base_url: default_issuer_base_url, client_id: default_client_id)
        status, body = post_json(
          uri: "#{issuer_base_url.to_s.chomp("/")}#{DEVICE_AUTH_USER_CODE_PATH}",
          json: { client_id: client_id }
        )
        raise_request_failure!("device auth usercode failed", status:, body:) unless status == 200

        {
          "device_auth_id" => fetch_required_string(body, "device_auth_id"),
          "user_code" => fetch_required_string(body, "user_code"),
          "verification_uri" => body["verification_uri"].presence || "#{issuer_base_url.to_s.chomp("/")}#{VERIFICATION_PATH}",
          "interval" => Integer(body.fetch("interval", 5)),
          "expires_at" => body["expires_at"],
        }.compact
      end

      def self.poll_device_flow!(device_auth_id:, user_code:, issuer_base_url: default_issuer_base_url, client_id: default_client_id)
        status, body = post_json(
          uri: "#{issuer_base_url.to_s.chomp("/")}#{DEVICE_AUTH_TOKEN_PATH}",
          json: {
            device_auth_id: device_auth_id.to_s,
            user_code: user_code.to_s,
          }
        )
        return { status: :pending, raw: body } if [403, 404].include?(status)
        raise_request_failure!("device auth poll failed", status:, body:) unless status == 200

        authorization_code = fetch_required_string(body, "authorization_code")
        code_verifier = fetch_required_string(body, "code_verifier")
        _token_status, token_body = post_form(
          uri: oauth_token_uri(issuer_base_url),
          form_data: {
            grant_type: "authorization_code",
            client_id: client_id,
            code: authorization_code,
            code_verifier: code_verifier,
            redirect_uri: "#{issuer_base_url.to_s.chomp("/")}#{DEVICE_AUTH_CALLBACK_PATH}",
          },
          allow_oauth_error: true
        )

        if (error_code = oauth_error_code(token_body))
          raise RequestFailed.new(
            "device flow token exchange failed: #{error_code}",
            status: 400,
            response_body: token_body,
            error_code: error_code
          )
        end

        tokens_from_token_response(token_body)
      end

      def self.default_issuer_base_url
        ENV.fetch("CODEX_SUBSCRIPTION_OAUTH_ISSUER_BASE_URL", DEFAULT_ISSUER_BASE_URL)
      end

      def self.default_client_id
        ENV.fetch("CODEX_SUBSCRIPTION_OAUTH_CLIENT_ID", DEFAULT_CLIENT_ID)
      end

      class << self
        private

        def oauth_token_uri(issuer_base_url)
          "#{issuer_base_url.to_s.chomp("/")}/oauth/token"
        end

        def post_form(uri:, form_data:, allow_oauth_error: false)
          request_uri = URI.parse(uri)
          request = Net::HTTP::Post.new(request_uri)
          request["Content-Type"] = "application/x-www-form-urlencoded"
          request.body = URI.encode_www_form(form_data)
          status, body = perform_request(request_uri, request)
          return [status, body] if status.between?(200, 299)
          return [status, body] if allow_oauth_error && oauth_error_code(body)

          raise_request_failure!("oauth token request failed", status:, body:)
        end

        def post_json(uri:, json:)
          request_uri = URI.parse(uri)
          request = Net::HTTP::Post.new(request_uri)
          request["Content-Type"] = "application/json"
          request["Accept"] = "application/json"
          request.body = JSON.generate(json)
          perform_request(request_uri, request)
        end

        def permanent_refresh_failure?(response_body)
          %w[
            invalid_grant
            refresh_token_expired
            refresh_token_reused
            refresh_token_invalidated
          ].include?(refresh_failure_reason(response_body))
        end

        def refresh_failure_reason(response_body, fallback: nil)
          return fallback if fallback.present?
          return response_body["error"] if response_body.is_a?(Hash) && response_body["error"].present?
          return response_body["error_code"] if response_body.is_a?(Hash) && response_body["error_code"].present?

          "token_refresh_failed"
        end

        def perform_request(uri, request)
          response =
            Net::HTTP.start(
              uri.host,
              uri.port,
              use_ssl: uri.scheme == "https"
            ) do |http|
              http.request(request)
            end

          [response.code.to_i, parse_json_body(response.body.to_s)]
        end

        def parse_json_body(body)
          parsed = body.to_s.strip.empty? ? {} : JSON.parse(body.to_s)
          parsed.is_a?(Hash) ? parsed : {}
        rescue JSON::ParserError
          { "raw_body" => body.to_s }
        end

        def oauth_error_code(body)
          return nil unless body.is_a?(Hash)

          code = body["error"] || body["error_code"]
          code.to_s.presence
        end

        def fetch_required_string(body, key)
          value = body[key]
          string = value.to_s
          raise_request_failure!("oauth response missing required field: #{key}", status: 502, body:) if string.blank?

          string
        end

        def raise_request_failure!(message, status:, body:)
          error_code = oauth_error_code(body)
          detail = body.is_a?(Hash) ? body["error_description"] || body["message"] || body.dig("error", "message") : nil
          composed_message = detail.present? ? "#{message}: #{detail}" : message
          raise RequestFailed.new(composed_message, status:, response_body: body, error_code:)
        end
      end
    end
  end
end
