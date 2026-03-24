module ProviderCredentials
  class UpsertSecret
    def self.call(...)
      new(...).call
    end

    def initialize(installation:, actor:, provider_handle:, credential_kind:, secret:, metadata: {}, rotated_at: Time.current)
      @installation = installation
      @actor = actor
      @provider_handle = provider_handle
      @credential_kind = credential_kind
      @secret = secret
      @metadata = metadata
      @rotated_at = rotated_at
    end

    def call
      ApplicationRecord.transaction do
        credential = ProviderCredential.find_or_initialize_by(
          installation: @installation,
          provider_handle: @provider_handle,
          credential_kind: @credential_kind
        )
        credential.assign_attributes(
          secret: @secret,
          metadata: @metadata,
          last_rotated_at: @rotated_at
        )
        credential.save!

        AuditLog.record!(
          installation: @installation,
          actor: @actor,
          action: "provider_credential.upserted",
          subject: credential,
          metadata: {
            provider_handle: @provider_handle,
            credential_kind: @credential_kind,
          }
        )

        credential
      end
    end
  end
end
