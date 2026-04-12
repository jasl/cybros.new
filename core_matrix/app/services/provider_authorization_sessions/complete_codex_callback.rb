module ProviderAuthorizationSessions
  class CompleteCodexCallback
    def self.call(...)
      new(...).call
    end

    def initialize(state:, code:, token_exchange: nil, redirect_uri: nil, issuer_base_url: LLMProviders::CodexSubscription::OAuthClient.default_issuer_base_url, client_id: LLMProviders::CodexSubscription::OAuthClient.default_client_id)
      @state = state
      @code = code
      @token_exchange = token_exchange
      @redirect_uri = redirect_uri
      @issuer_base_url = issuer_base_url
      @client_id = client_id
    end

    def call
      ApplicationRecord.transaction do
        authorization_session = ProviderAuthorizationSessions::ResolveFromState.call(
          state: @state,
          provider_handle: "codex_subscription"
        )
        token_attributes = exchange_tokens(authorization_session)
        credential = upsert_credential!(authorization_session:, token_attributes:)

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

        credential
      end
    end

    private

    def exchange_tokens(authorization_session)
      exchange = @token_exchange || default_token_exchange
      exchange.call(
        code: @code,
        redirect_uri: @redirect_uri,
        code_verifier: authorization_session.pkce_verifier,
        issuer_base_url: @issuer_base_url,
        client_id: @client_id
      )
    end

    def default_token_exchange
      lambda do |**kwargs|
        LLMProviders::CodexSubscription::OAuthClient.exchange_code(**kwargs)
      end
    end

    def upsert_credential!(authorization_session:, token_attributes:)
      credential = ProviderCredential.find_or_initialize_by(
        installation: authorization_session.installation,
        provider_handle: authorization_session.provider_handle,
        credential_kind: "oauth_codex"
      )
      credential.assign_attributes(
        secret: nil,
        access_token: token_attributes.fetch(:access_token),
        refresh_token: token_attributes.fetch(:refresh_token),
        expires_at: token_attributes.fetch(:expires_at),
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
