class PublicationAccessEvent < ApplicationRecord
  belongs_to :installation
  belongs_to :publication
  belongs_to :viewer_user, class_name: "User", optional: true

  validates :access_via, presence: true
  validates :accessed_at, presence: true
  validate :request_metadata_must_be_hash
  validate :publication_installation_match
  validate :viewer_user_installation_match

  private

  def request_metadata_must_be_hash
    errors.add(:request_metadata, "must be a hash") unless request_metadata.is_a?(Hash)
  end

  def publication_installation_match
    return if publication.blank?
    return if publication.installation_id == installation_id

    errors.add(:publication, "must belong to the same installation")
  end

  def viewer_user_installation_match
    return if viewer_user.blank?
    return if viewer_user.installation_id == installation_id

    errors.add(:viewer_user, "must belong to the same installation")
  end
end
