module Publications
  class PublishLive
    ALLOWED_VISIBILITY_MODES = %w[internal_public external_public].freeze

    def self.call(...)
      new(...).call
    end

    def initialize(conversation:, actor:, visibility_mode:, published_at: Time.current)
      @conversation = conversation
      @actor = actor
      @visibility_mode = visibility_mode.to_s
      @published_at = published_at
    end

    def call
      raise ArgumentError, "visibility mode must publish the conversation" unless ALLOWED_VISIBILITY_MODES.include?(@visibility_mode)
      Conversations::WithRetainedStateLock.call(
        conversation: @conversation,
        record: @conversation,
        message: "must be retained before publishing"
      ) do |conversation|
        publication = Publication.find_or_initialize_by(conversation: conversation)
        previously_active = publication.persisted? && publication.active?
        previous_visibility_mode = publication.visibility_mode

        assign_publication_attributes!(
          publication,
          conversation: conversation,
          previously_active: previously_active,
          previous_visibility_mode: previous_visibility_mode
        )
        publication.save!

        record_audit!(publication, previously_active, previous_visibility_mode)
        publication
      end
    end

    private

    def assign_publication_attributes!(publication, conversation:, previously_active:, previous_visibility_mode:)
      publication.installation = conversation.installation
      publication.owner_user = conversation.workspace.user
      publication.visibility_mode = @visibility_mode
      publication.slug ||= Publication.issue_slug
      publication.published_at = previously_active ? publication.published_at : @published_at
      publication.revoked_at = nil

      if publication.access_token_digest.blank? || previous_visibility_mode != @visibility_mode
        plaintext_access_token, digest = Publication.issue_access_token_pair
        publication.access_token_digest = digest
        publication.remember_plaintext_access_token!(plaintext_access_token)
      end
    end

    def record_audit!(publication, previously_active, previous_visibility_mode)
      action =
        if !previously_active
          "publication.enabled"
        elsif previous_visibility_mode != @visibility_mode
          "publication.visibility_changed"
        end
      return if action.blank?

      AuditLog.record!(
        installation: publication.installation,
        action: action,
        actor: @actor,
        subject: publication,
        metadata: {
          "visibility_mode" => publication.visibility_mode,
          "previous_visibility_mode" => previous_visibility_mode,
          "conversation_id" => publication.conversation_id,
        }.compact
      )
    end
  end
end
