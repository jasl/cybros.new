class ConversationExportRequest < ApplicationRecord
  include HasPublicId
  include DataLifecycle

  enum :lifecycle_state,
    {
      queued: "queued",
      running: "running",
      succeeded: "succeeded",
      failed: "failed",
      expired: "expired",
    },
    validate: true

  belongs_to :installation
  belongs_to :workspace
  belongs_to :conversation
  belongs_to :user

  has_one_attached :bundle_file

  validates :expires_at, presence: true
  validate :request_payload_must_be_hash
  validate :result_payload_must_be_hash
  validate :failure_payload_must_be_hash
  validate :workspace_installation_match
  validate :conversation_installation_match
  validate :conversation_workspace_match
  validate :user_installation_match
  validate :bundle_file_required_when_succeeded

  data_lifecycle_kind! :ephemeral_observability

  private

  def request_payload_must_be_hash
    errors.add(:request_payload, "must be a hash") unless request_payload.is_a?(Hash)
  end

  def result_payload_must_be_hash
    errors.add(:result_payload, "must be a hash") unless result_payload.is_a?(Hash)
  end

  def failure_payload_must_be_hash
    errors.add(:failure_payload, "must be a hash") unless failure_payload.is_a?(Hash)
  end

  def workspace_installation_match
    return if workspace.blank? || workspace.installation_id == installation_id

    errors.add(:workspace, "must belong to the same installation")
  end

  def conversation_installation_match
    return if conversation.blank? || conversation.installation_id == installation_id

    errors.add(:conversation, "must belong to the same installation")
  end

  def conversation_workspace_match
    return if conversation.blank? || workspace.blank?
    return if conversation.workspace_id == workspace_id

    errors.add(:conversation, "must belong to the same workspace")
  end

  def user_installation_match
    return if user.blank? || user.installation_id == installation_id

    errors.add(:user, "must belong to the same installation")
  end

  def bundle_file_required_when_succeeded
    return unless succeeded?
    return if bundle_file.attached?

    errors.add(:bundle_file, "must be attached once the export succeeds")
  end
end
