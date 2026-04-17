require "time"

module CoreMatrixCLI
  module UseCases
    class AuthorizeCodexSubscription < Base
      FALLBACK_POLL_TIMEOUT = 900
      DEFAULT_POLL_INTERVAL = 5.0

      def call
        initial_payload = authenticated_api.start_codex_authorization
        initial_authorization = initial_payload.fetch("authorization")

        open_verification_uri(initial_authorization)

        final_payload = polling.until(
          timeout: poll_timeout_seconds_for(initial_authorization),
          interval: poll_interval_seconds_for(initial_authorization),
          stop_on: ->(payload) { payload.dig("authorization", "status") != "pending" }
        ) do
          authenticated_api.poll_codex_authorization
        end

        {
          initial_authorization: initial_authorization,
          final_authorization: final_payload.fetch("authorization"),
        }
      end

      private

      def open_verification_uri(authorization)
        verification_uri = authorization["verification_uri"]
        return if verification_uri.to_s.strip.empty?

        browser_launcher&.open(verification_uri)
      end

      def poll_interval_seconds_for(authorization)
        raw = authorization["poll_interval_seconds"]
        interval = raw.nil? ? DEFAULT_POLL_INTERVAL : raw.to_f
        interval.positive? ? interval : 0.0
      end

      def poll_timeout_seconds_for(authorization)
        expires_at = parse_time(authorization["expires_at"])
        return FALLBACK_POLL_TIMEOUT unless expires_at

        remaining = expires_at - time_source.call
        remaining.positive? ? remaining : 0.0
      end

      def parse_time(value)
        return nil if value.to_s.strip.empty?

        Time.iso8601(value.to_s)
      rescue ArgumentError
        nil
      end
    end
  end
end
