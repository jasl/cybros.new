module ProviderAuthorizationSessions
  class Poll
    NoActiveSession = Class.new(StandardError)
    TerminalPollFailure = Class.new(StandardError)

    def self.call(...)
      new(...).call
    end

    def initialize(installation:, provider_handle:, device_flow_poll: nil)
      @installation = installation
      @provider_handle = provider_handle
      @device_flow_poll = device_flow_poll
    end

    def call
      authorization_session = active_authorization_session
      raise NoActiveSession, "no active device flow. start it first." if authorization_session.blank?

      result = poll_device_flow(authorization_session)
      return { status: :pending, authorization_session: authorization_session } if result.fetch(:status) == :pending

      ApplicationRecord.transaction do
        credential = upsert_credential!(
          authorization_session: authorization_session,
          token_attributes: result.fetch(:tokens)
        )
        authorization_session.complete!

        AuditLog.record!(
          installation: authorization_session.installation,
          actor: authorization_session.issued_by_user,
          action: "provider_authorization_session.completed",
          subject: authorization_session,
          metadata: {
            "provider_handle" => authorization_session.provider_handle,
          }
        )

        {
          status: :authorized,
          authorization_session: authorization_session,
          credential: credential,
        }
      end
    rescue LLMProviders::CodexSubscription::OAuthClient::RequestFailed => error
      authorization_session&.revoke! if authorization_session && error.client_error?
      raise TerminalPollFailure, error.message if error.client_error?

      raise
    end

    private

    def active_authorization_session
      ProviderAuthorizationSession.where(
        installation: @installation,
        provider_handle: @provider_handle,
        status: "pending"
      ).where("expires_at > ?", Time.current).order(issued_at: :desc, id: :desc).first
    end

    def poll_device_flow(authorization_session)
      (@device_flow_poll || default_device_flow_poll).call(
        device_auth_id: authorization_session.device_auth_id,
        user_code: authorization_session.user_code
      )
    end

    def default_device_flow_poll
      ->(**kwargs) { LLMProviders::CodexSubscription::OAuthClient.poll_device_flow!(**kwargs) }
    end

    def upsert_credential!(authorization_session:, token_attributes:)
      credential = ProviderCredential.find_or_initialize_by(
        installation: authorization_session.installation,
        provider_handle: authorization_session.provider_handle,
        credential_kind: "oauth_codex"
      )
      credential.assign_attributes(
        secret: nil,
        access_token: token_attributes.fetch("access_token"),
        refresh_token: token_attributes.fetch("refresh_token", credential.refresh_token),
        expires_at: token_attributes.fetch("expires_at"),
        last_rotated_at: Time.current,
        last_refreshed_at: nil,
        refresh_failed_at: nil,
        refresh_failure_reason: nil,
        metadata: credential.metadata || {}
      )
      credential.save!
      credential
    end
  end
end
