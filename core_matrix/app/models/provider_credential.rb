class ProviderCredential < ApplicationRecord
  encrypts :secret
  encrypts :access_token
  encrypts :refresh_token

  belongs_to :installation

  validates :provider_handle, presence: true, uniqueness: { scope: [:installation_id, :credential_kind] }
  validates :credential_kind, presence: true
  validates :last_rotated_at, presence: true
  validate :metadata_must_be_hash
  validate :credential_shape_matches_kind

  def oauth_codex?
    credential_kind == "oauth_codex"
  end

  def reauthorization_required?
    refresh_failed_at.present?
  end

  def access_token_expired?
    expires_at.present? && expires_at <= Time.current
  end

  def usable_for_provider_requests?
    return secret.present? unless oauth_codex?

    access_token.present? && refresh_token.present? && !reauthorization_required?
  end

  private

  def metadata_must_be_hash
    errors.add(:metadata, "must be a Hash") unless metadata.is_a?(Hash)
  end

  def credential_shape_matches_kind
    if oauth_codex?
      errors.add(:secret, "must be blank for oauth_codex") if secret.present?
      errors.add(:access_token, "can't be blank") if access_token.blank?
      errors.add(:refresh_token, "can't be blank") if refresh_token.blank?
      errors.add(:expires_at, "can't be blank") if expires_at.blank?
      return
    end

    errors.add(:secret, "can't be blank") if secret.blank?
    errors.add(:access_token, "must be blank for non-oauth credentials") if access_token.present?
    errors.add(:refresh_token, "must be blank for non-oauth credentials") if refresh_token.present?
    errors.add(:expires_at, "must be blank for non-oauth credentials") if expires_at.present?
    errors.add(:last_refreshed_at, "must be blank for non-oauth credentials") if last_refreshed_at.present?
    errors.add(:refresh_failed_at, "must be blank for non-oauth credentials") if refresh_failed_at.present?
    errors.add(:refresh_failure_reason, "must be blank for non-oauth credentials") if refresh_failure_reason.present?
  end
end
