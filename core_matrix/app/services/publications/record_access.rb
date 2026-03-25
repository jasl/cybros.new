module Publications
  class RecordAccess
    def self.call(...)
      new(...).call
    end

    def initialize(publication: nil, slug: nil, access_token: nil, viewer_user: nil, request_metadata: {}, accessed_at: Time.current)
      @publication = publication
      @slug = slug
      @access_token = access_token
      @viewer_user = viewer_user
      @request_metadata = request_metadata
      @accessed_at = accessed_at
    end

    def call
      publication = resolve_publication
      validate_publication_access!(publication)

      PublicationAccessEvent.create!(
        installation: publication.installation,
        publication: publication,
        viewer_user: @viewer_user,
        access_via: access_via,
        accessed_at: @accessed_at,
        request_metadata: @request_metadata
      )
    end

    private

    def resolve_publication
      return @publication if @publication.present?
      return Publication.find_by!(slug: @slug) if @slug.present?

      publication = Publication.find_by_plaintext_access_token(@access_token)
      return publication if publication.present?

      raise ActiveRecord::RecordNotFound, "publication is not present"
    end

    def validate_publication_access!(publication)
      raise_invalid!(publication, :visibility_mode, "must be published for read-only access") unless publication.active?
      raise_invalid!(publication, :conversation, "must be retained for read-only access") unless publication.conversation.retained?

      if publication.internal_public?
        raise_invalid!(publication, :viewer_user, "must exist for internal public access") if @viewer_user.blank?
        if @viewer_user.installation_id != publication.installation_id
          raise_invalid!(publication, :viewer_user, "must belong to the same installation")
        end
      elsif @viewer_user.present? && @viewer_user.installation_id != publication.installation_id
        raise_invalid!(publication, :viewer_user, "must belong to the same installation")
      end
    end

    def access_via
      return "publication" if @publication.present?
      return "slug" if @slug.present?

      "access_token"
    end

    def raise_invalid!(record, attribute, message)
      record.errors.add(attribute, message)
      raise ActiveRecord::RecordInvalid, record
    end
  end
end
