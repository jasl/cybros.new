class ConversationBundleImportRequest < ApplicationRecord
  include HasPublicId

  enum :lifecycle_state,
    {
      queued: "queued",
      running: "running",
      succeeded: "succeeded",
      failed: "failed",
    },
    validate: true

  belongs_to :installation
  belongs_to :workspace
  belongs_to :user
  belongs_to :imported_conversation, class_name: "Conversation", optional: true

  has_one_attached :upload_file

  validate :request_payload_must_be_hash
  validate :result_payload_must_be_hash
  validate :failure_payload_must_be_hash
  validate :workspace_installation_match
  validate :user_installation_match
  validate :imported_conversation_installation_match
  validate :imported_conversation_workspace_match
  validate :upload_file_presence

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

  def user_installation_match
    return if user.blank? || user.installation_id == installation_id

    errors.add(:user, "must belong to the same installation")
  end

  def imported_conversation_installation_match
    return if imported_conversation.blank? || imported_conversation.installation_id == installation_id

    errors.add(:imported_conversation, "must belong to the same installation")
  end

  def imported_conversation_workspace_match
    return if imported_conversation.blank? || workspace.blank?
    return if imported_conversation.workspace_id == workspace_id

    errors.add(:imported_conversation, "must belong to the same workspace")
  end

  def upload_file_presence
    return if upload_file.attached?

    errors.add(:upload_file, "must be attached")
  end
end
