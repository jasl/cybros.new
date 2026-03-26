class ConversationImport < ApplicationRecord
  enum :kind,
    {
      branch_prefix: "branch_prefix",
      merge_summary: "merge_summary",
      quoted_context: "quoted_context",
    },
    validate: true

  belongs_to :installation
  belongs_to :conversation
  belongs_to :source_conversation, class_name: "Conversation", optional: true
  belongs_to :source_message, class_name: "Message", optional: true
  belongs_to :summary_segment, class_name: "ConversationSummarySegment", optional: true

  before_validation :sync_source_conversation

  validates :kind, uniqueness: { scope: :conversation_id }, if: :branch_prefix?
  validate :conversation_installation_match
  validate :source_conversation_installation_match
  validate :source_message_installation_match
  validate :summary_segment_installation_match
  validate :source_message_belongs_to_source_conversation
  validate :kind_requirements

  private

  def sync_source_conversation
    self.source_conversation ||= summary_segment&.conversation || source_message&.conversation
  end

  def conversation_installation_match
    return if conversation.blank?
    return if conversation.installation_id == installation_id

    errors.add(:conversation, "must belong to the same installation")
  end

  def source_conversation_installation_match
    return if source_conversation.blank?
    return if source_conversation.installation_id == installation_id

    errors.add(:source_conversation, "must belong to the same installation")
  end

  def source_message_installation_match
    return if source_message.blank?
    return if source_message.installation_id == installation_id

    errors.add(:source_message, "must belong to the same installation")
  end

  def summary_segment_installation_match
    return if summary_segment.blank?
    return if summary_segment.installation_id == installation_id

    errors.add(:summary_segment, "must belong to the same installation")
  end

  def source_message_belongs_to_source_conversation
    return if source_message.blank? || source_conversation.blank?

    if source_conversation.transcript_projection_includes?(source_message)
      return
    end

    errors.add(:source_message, "must be present in the source conversation transcript projection")
  end

  def kind_requirements
    return if kind.blank?

    if branch_prefix?
      errors.add(:source_conversation, "must exist for branch_prefix imports") if source_conversation.blank?
      errors.add(:source_message, "must exist for branch_prefix imports") if source_message.blank?
      errors.add(:summary_segment, "must be blank for branch_prefix imports") if summary_segment.present?
      validate_branch_prefix_anchor
      return
    end

    if merge_summary?
      errors.add(:summary_segment, "must exist for merge_summary imports") if summary_segment.blank?
      errors.add(:source_message, "must be blank for merge_summary imports") if source_message.present?
      return
    end

    return if source_message.present? || summary_segment.present?

    errors.add(:base, "must reference a summary segment or source message for quoted_context imports")
  end

  def validate_branch_prefix_anchor
    return if conversation.blank?

    errors.add(:conversation, "must be a branch conversation for branch_prefix imports") unless conversation.branch?
    return if errors.any?

    unless conversation.parent_conversation_id == source_conversation_id
      errors.add(:source_conversation, "must match the branch parent conversation")
    end
    return if source_message.blank?

    return if conversation.historical_anchor_message_id == source_message_id

    errors.add(:source_message, "must match the branch anchor message")
  end
end
