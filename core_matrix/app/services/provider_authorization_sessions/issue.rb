module ProviderAuthorizationSessions
  class Issue
    DEFAULT_EXPIRY = 15.minutes
    DEFAULT_POLL_INTERVAL_SECONDS = 5

    def self.call(...)
      new(...).call
    end

    def initialize(installation:, actor:, provider_handle:, device_flow_start: nil, expires_at: DEFAULT_EXPIRY.from_now)
      @installation = installation
      @actor = actor
      @provider_handle = provider_handle
      @device_flow_start = device_flow_start
      @expires_at = expires_at
    end

    def call
      ApplicationRecord.transaction do
        revoke_pending_sessions!
        device_flow = start_device_flow

        authorization_session = ProviderAuthorizationSession.issue!(
          installation: @installation,
          provider_handle: @provider_handle,
          issued_by_user: @actor,
          device_auth_id: device_flow.fetch("device_auth_id"),
          user_code: device_flow.fetch("user_code"),
          verification_uri: device_flow.fetch("verification_uri"),
          poll_interval_seconds: Integer(device_flow.fetch("interval", DEFAULT_POLL_INTERVAL_SECONDS)),
          expires_at: parse_expires_at(device_flow["expires_at"]) || @expires_at
        )

        AuditLog.record!(
          installation: @installation,
          actor: @actor,
          action: "provider_authorization_session.issued",
          subject: authorization_session,
          metadata: {
            "provider_handle" => @provider_handle,
          }
        )

        {
          authorization_session: authorization_session,
        }
      end
    end

    private

    def start_device_flow
      (@device_flow_start || default_device_flow_start).call
    end

    def default_device_flow_start
      -> { LLMProviders::CodexSubscription::OAuthClient.start_device_flow! }
    end

    def parse_expires_at(value)
      return value if value.is_a?(Time)
      return nil if value.blank?

      Time.iso8601(value.to_s)
    rescue ArgumentError
      nil
    end

    def revoke_pending_sessions!
      ProviderAuthorizationSession.where(
        installation: @installation,
        provider_handle: @provider_handle,
        status: "pending"
      ).find_each(&:revoke!)
    end
  end
end
