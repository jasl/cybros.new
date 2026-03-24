module Publications
  class Revoke
    def self.call(...)
      new(...).call
    end

    def initialize(publication:, actor:, revoked_at: Time.current)
      @publication = publication
      @actor = actor
      @revoked_at = revoked_at
    end

    def call
      raise_invalid!(@publication, :visibility_mode, "must be published before revocation") unless @publication.active?

      previous_visibility_mode = @publication.visibility_mode

      ApplicationRecord.transaction do
        @publication.update!(
          visibility_mode: "disabled",
          revoked_at: @revoked_at
        )

        AuditLog.record!(
          installation: @publication.installation,
          action: "publication.revoked",
          actor: @actor,
          subject: @publication,
          metadata: {
            "previous_visibility_mode" => previous_visibility_mode,
            "conversation_id" => @publication.conversation_id,
          }
        )

        @publication
      end
    end

    private

    def raise_invalid!(record, attribute, message)
      record.errors.add(attribute, message)
      raise ActiveRecord::RecordInvalid, record
    end
  end
end
