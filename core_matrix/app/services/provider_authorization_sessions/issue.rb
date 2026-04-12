module ProviderAuthorizationSessions
  class Issue
    DEFAULT_EXPIRY = 15.minutes

    def self.call(...)
      new(...).call
    end

    def initialize(installation:, actor:, provider_handle:, redirect_uri:, issuer_base_url: LLMProviders::CodexSubscription::OAuthClient.default_issuer_base_url, client_id: LLMProviders::CodexSubscription::OAuthClient.default_client_id, expires_at: DEFAULT_EXPIRY.from_now)
      @installation = installation
      @actor = actor
      @provider_handle = provider_handle
      @redirect_uri = redirect_uri
      @issuer_base_url = issuer_base_url
      @client_id = client_id
      @expires_at = expires_at
    end

    def call
      ApplicationRecord.transaction do
        revoke_pending_sessions!

        authorization_session = ProviderAuthorizationSession.issue!(
          installation: @installation,
          provider_handle: @provider_handle,
          issued_by_user: @actor,
          expires_at: @expires_at
        )
        authorization_url = LLMProviders::CodexSubscription::OAuthClient.authorization_url(
          redirect_uri: @redirect_uri,
          state: authorization_session.plaintext_state,
          code_challenge: ProviderAuthorizationSession.code_challenge_for(authorization_session.plaintext_pkce_verifier),
          issuer_base_url: @issuer_base_url,
          client_id: @client_id
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
          authorization_url: authorization_url,
        }
      end
    end

    private

    def revoke_pending_sessions!
      ProviderAuthorizationSession.where(
        installation: @installation,
        provider_handle: @provider_handle,
        status: "pending"
      ).find_each(&:revoke!)
    end
  end
end
