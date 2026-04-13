class LineageStore < ApplicationRecord
  belongs_to :installation
  belongs_to :workspace
  belongs_to :owner_conversation, class_name: "Conversation"

  has_many :lineage_store_snapshots, dependent: :restrict_with_exception

  validate :owner_conversation_workspace_match
  validate :owner_conversation_installation_match

  private

  def owner_conversation_workspace_match
    return if owner_conversation.blank? || workspace.blank?
    return if owner_conversation.workspace_id == workspace_id

    errors.add(:workspace, "must match the owner conversation workspace")
  end

  def owner_conversation_installation_match
    return if owner_conversation.blank? || installation.blank?
    return if owner_conversation.installation_id == installation_id

    errors.add(:installation, "must match the owner conversation installation")
  end
end
