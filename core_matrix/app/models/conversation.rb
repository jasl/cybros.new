class Conversation < ApplicationRecord
  enum :kind,
    {
      root: "root",
      branch: "branch",
      thread: "thread",
      checkpoint: "checkpoint",
    },
    validate: true
  enum :purpose,
    {
      interactive: "interactive",
      automation: "automation",
    },
    validate: true
  enum :lifecycle_state,
    {
      active: "active",
      archived: "archived",
    },
    validate: true

  belongs_to :installation
  belongs_to :workspace
  belongs_to :parent_conversation, class_name: "Conversation", optional: true

  has_many :child_conversations,
    class_name: "Conversation",
    foreign_key: :parent_conversation_id,
    dependent: :restrict_with_exception,
    inverse_of: :parent_conversation
  has_many :ancestor_closures,
    class_name: "ConversationClosure",
    foreign_key: :descendant_conversation_id,
    dependent: :restrict_with_exception,
    inverse_of: :descendant_conversation
  has_many :descendant_closures,
    class_name: "ConversationClosure",
    foreign_key: :ancestor_conversation_id,
    dependent: :restrict_with_exception,
    inverse_of: :ancestor_conversation

  validate :workspace_installation_match
  validate :parent_lineage_rules
  validate :parent_workspace_match
  validate :automation_rules

  private

  def workspace_installation_match
    return if workspace.blank?
    return if workspace.installation_id == installation_id

    errors.add(:workspace, "must belong to the same installation")
  end

  def parent_lineage_rules
    return if kind.blank?

    if root?
      errors.add(:parent_conversation, "must be blank for root conversations") if parent_conversation.present?
      errors.add(:historical_anchor_message_id, "must be blank for root conversations") if historical_anchor_message_id.present?
      return
    end

    errors.add(:parent_conversation, "must exist") if parent_conversation.blank?
    errors.add(:historical_anchor_message_id, "must exist") if (branch? || checkpoint?) && historical_anchor_message_id.blank?
  end

  def automation_rules
    return unless automation?

    errors.add(:kind, "must be root for automation conversations") unless root?
  end

  def parent_workspace_match
    return if parent_conversation.blank?
    return if parent_conversation.workspace_id == workspace_id

    errors.add(:workspace, "must match the parent conversation workspace")
  end
end
