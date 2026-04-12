require "json"
require "net/http"
require "uri"

module LLMProviders
  module CodexSubscription
    class OAuthClient
      DEFAULT_ISSUER_BASE_URL = "https://auth.openai.com".freeze
      DEFAULT_CLIENT_ID = "app_EMoamEEZ73f0CkXaXp7hrann".freeze
      DEFAULT_SCOPES = [
        "openid",
        "profile",
        "email",
        "offline_access",
        "api.connectors.read",
        "api.connectors.invoke",
      ].freeze

      def self.authorization_url(redirect_uri:, state:, code_challenge:, issuer_base_url: default_issuer_base_url, client_id: default_client_id)
        query = URI.encode_www_form(
          response_type: "code",
          client_id: client_id,
          redirect_uri: redirect_uri,
          scope: DEFAULT_SCOPES.join(" "),
          code_challenge: code_challenge,
          code_challenge_method: "S256",
          id_token_add_organizations: "true",
          codex_cli_simplified_flow: "true",
          state: state
        )

        "#{issuer_base_url.to_s.chomp("/")}/oauth/authorize?#{query}"
      end

      def self.exchange_code(code:, redirect_uri:, code_verifier:, issuer_base_url: default_issuer_base_url, client_id: default_client_id)
        response = post_form(
          uri: "#{issuer_base_url.to_s.chomp("/")}/oauth/token",
          form_data: {
            grant_type: "authorization_code",
            code: code,
            redirect_uri: redirect_uri,
            client_id: client_id,
            code_verifier: code_verifier,
          }
        )

        body = parse_json_body(response)
        {
          access_token: body.fetch("access_token"),
          refresh_token: body.fetch("refresh_token"),
          expires_at: Time.current + body.fetch("expires_in").to_i.seconds,
        }
      end

      def self.refresh_tokens(refresh_token:, issuer_base_url: default_issuer_base_url, client_id: default_client_id)
        response = post_form(
          uri: "#{issuer_base_url.to_s.chomp("/")}/oauth/token",
          form_data: {
            grant_type: "refresh_token",
            refresh_token: refresh_token,
            client_id: client_id,
          }
        )

        body = parse_json_body(response)
        {
          access_token: body.fetch("access_token"),
          refresh_token: body["refresh_token"],
          expires_at: Time.current + body.fetch("expires_in").to_i.seconds,
        }
      rescue TokenRequestFailed => error
        raise error unless permanent_refresh_failure?(error.response_body)

        raise ProviderCredentials::RefreshOAuthCredential::PermanentRefreshFailure.new(
          reason: refresh_failure_reason(error.response_body),
          message: error.message
        )
      end

      def self.default_issuer_base_url
        ENV.fetch("CODEX_SUBSCRIPTION_OAUTH_ISSUER_BASE_URL", DEFAULT_ISSUER_BASE_URL)
      end

      def self.default_client_id
        ENV.fetch("CODEX_SUBSCRIPTION_OAUTH_CLIENT_ID", DEFAULT_CLIENT_ID)
      end

      class TokenRequestFailed < StandardError
        attr_reader :status, :response_body

        def initialize(status:, response_body:)
          super("oauth token request failed with status #{status}")
          @status = status
          @response_body = response_body
        end
      end

      class << self
        private

        def post_form(uri:, form_data:)
          request_uri = URI.parse(uri)
          request = Net::HTTP::Post.new(request_uri)
          request["Content-Type"] = "application/x-www-form-urlencoded"
          request.body = URI.encode_www_form(form_data)

          Net::HTTP.start(
            request_uri.host,
            request_uri.port,
            use_ssl: request_uri.scheme == "https"
          ) do |http|
            response = http.request(request)
            return response if response.is_a?(Net::HTTPSuccess)

            raise TokenRequestFailed.new(status: response.code.to_i, response_body: response.body.to_s)
          end
        end

        def parse_json_body(response)
          JSON.parse(response.body.to_s)
        rescue JSON::ParserError => error
          raise TokenRequestFailed.new(status: response.code.to_i, response_body: response.body.to_s), error.message
        end

        def permanent_refresh_failure?(response_body)
          %w[
            invalid_grant
            refresh_token_expired
            refresh_token_reused
            refresh_token_invalidated
          ].include?(refresh_failure_reason(response_body))
        end

        def refresh_failure_reason(response_body)
          body = JSON.parse(response_body.to_s)
          body["error"].presence || body["error_code"].presence || "token_refresh_failed"
        rescue JSON::ParserError
          "token_refresh_failed"
        end
      end
    end
  end
end
