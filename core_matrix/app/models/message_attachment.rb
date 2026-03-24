class MessageAttachment < ApplicationRecord
  belongs_to :installation
  belongs_to :conversation
  belongs_to :message
  belongs_to :origin_attachment, class_name: "MessageAttachment", optional: true
  belongs_to :origin_message, class_name: "Message", optional: true

  has_one_attached :file

  before_validation :sync_origin_message_from_origin_attachment

  validates_presence_of :file
  validate :conversation_installation_match
  validate :message_installation_match
  validate :message_conversation_match
  validate :origin_attachment_installation_match
  validate :origin_message_installation_match
  validate :origin_attachment_message_match

  private

  def sync_origin_message_from_origin_attachment
    return if origin_attachment.blank?

    self.origin_message ||= origin_attachment.origin_message || origin_attachment.message
  end

  def conversation_installation_match
    return if conversation.blank?
    return if conversation.installation_id == installation_id

    errors.add(:conversation, "must belong to the same installation")
  end

  def message_installation_match
    return if message.blank?
    return if message.installation_id == installation_id

    errors.add(:message, "must belong to the same installation")
  end

  def message_conversation_match
    return if message.blank? || conversation.blank?
    return if message.conversation_id == conversation_id

    errors.add(:conversation, "must match the message conversation")
  end

  def origin_attachment_installation_match
    return if origin_attachment.blank?
    return if origin_attachment.installation_id == installation_id

    errors.add(:origin_attachment, "must belong to the same installation")
  end

  def origin_message_installation_match
    return if origin_message.blank?
    return if origin_message.installation_id == installation_id

    errors.add(:origin_message, "must belong to the same installation")
  end

  def origin_attachment_message_match
    return if origin_attachment.blank? || origin_message.blank?
    return if origin_attachment.origin_message == origin_message || origin_attachment.message == origin_message

    errors.add(:origin_message, "must match the origin attachment ancestry")
  end
end
