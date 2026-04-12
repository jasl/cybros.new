module ProviderCredentials
  class RefreshOAuthCredential
    class PermanentRefreshFailure < StandardError
      attr_reader :reason

      def initialize(reason:, message:)
        super(message)
        @reason = reason
      end
    end

    class ReauthorizationRequired < StandardError
      attr_reader :reason

      def initialize(reason:, message:)
        super(message)
        @reason = reason
      end
    end

    def self.call(...)
      new(...).call
    end

    def initialize(installation:, provider_handle:, credential: nil, token_refresh: nil, issuer_base_url: LLMProviders::CodexSubscription::OAuthClient.default_issuer_base_url, client_id: LLMProviders::CodexSubscription::OAuthClient.default_client_id)
      @installation = installation
      @provider_handle = provider_handle
      @credential = credential
      @token_refresh = token_refresh
      @issuer_base_url = issuer_base_url
      @client_id = client_id
    end

    def call
      credential = @credential || find_credential!
      raise ReauthorizationRequired.new(reason: credential.refresh_failure_reason, message: "oauth credential requires reauthorization") if credential.reauthorization_required?
      return credential unless credential.access_token_expired?

      token_attributes = refresh_tokens(credential)
      credential.update!(
        access_token: token_attributes.fetch(:access_token),
        refresh_token: token_attributes[:refresh_token].presence || credential.refresh_token,
        expires_at: token_attributes.fetch(:expires_at),
        last_refreshed_at: Time.current,
        refresh_failed_at: nil,
        refresh_failure_reason: nil
      )

      AuditLog.record!(
        installation: @installation,
        action: "provider_credential.refreshed",
        subject: credential,
        metadata: {
          "provider_handle" => @provider_handle,
          "credential_kind" => credential.credential_kind,
        }
      )

      credential
    rescue PermanentRefreshFailure => error
      credential.update!(
        refresh_failed_at: Time.current,
        refresh_failure_reason: error.reason
      )

      AuditLog.record!(
        installation: @installation,
        action: "provider_credential.refresh_failed",
        subject: credential,
        metadata: {
          "provider_handle" => @provider_handle,
          "credential_kind" => credential.credential_kind,
          "reason" => error.reason,
        }
      )

      raise ReauthorizationRequired.new(reason: error.reason, message: error.message)
    end

    private

    def find_credential!
      ProviderCredential.find_by!(
        installation: @installation,
        provider_handle: @provider_handle,
        credential_kind: "oauth_codex"
      )
    end

    def refresh_tokens(credential)
      refresh = @token_refresh || default_token_refresh
      refresh.call(
        refresh_token: credential.refresh_token,
        issuer_base_url: @issuer_base_url,
        client_id: @client_id
      )
    end

    def default_token_refresh
      lambda do |**kwargs|
        LLMProviders::CodexSubscription::OAuthClient.refresh_tokens(**kwargs)
      end
    end
  end
end
