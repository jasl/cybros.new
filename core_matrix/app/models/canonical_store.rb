class CanonicalStore < ApplicationRecord
  belongs_to :installation
  belongs_to :workspace
  belongs_to :root_conversation, class_name: "Conversation"

  has_many :canonical_store_snapshots, dependent: :restrict_with_exception

  validate :root_conversation_workspace_match
  validate :root_conversation_installation_match

  private

  def root_conversation_workspace_match
    return if root_conversation.blank? || workspace.blank?
    return if root_conversation.workspace_id == workspace_id

    errors.add(:workspace, "must match the root conversation workspace")
  end

  def root_conversation_installation_match
    return if root_conversation.blank? || installation.blank?
    return if root_conversation.installation_id == installation_id

    errors.add(:installation, "must match the root conversation installation")
  end
end
