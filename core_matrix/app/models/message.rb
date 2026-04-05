class Message < ApplicationRecord
  include HasPublicId
  include DataLifecycle

  TRANSCRIPT_BEARING_TYPES = %w[UserMessage AgentMessage].freeze

  enum :role, { user: "user", agent: "agent" }, validate: true
  enum :slot, { input: "input", output: "output" }, validate: true

  data_lifecycle_kind! :owner_bound

  belongs_to :installation
  belongs_to :conversation
  belongs_to :turn
  belongs_to :source_input_message, class_name: "Message", optional: true

  has_many :conversation_message_visibilities, dependent: :restrict_with_exception
  has_many :message_attachments, dependent: :restrict_with_exception
  has_many :starting_summary_segments,
    class_name: "ConversationSummarySegment",
    foreign_key: :start_message_id,
    dependent: :restrict_with_exception,
    inverse_of: :start_message
  has_many :ending_summary_segments,
    class_name: "ConversationSummarySegment",
    foreign_key: :end_message_id,
    dependent: :restrict_with_exception,
    inverse_of: :end_message
  has_many :source_conversation_imports,
    class_name: "ConversationImport",
    foreign_key: :source_message_id,
    dependent: :restrict_with_exception,
    inverse_of: :source_message
  has_many :origin_process_runs,
    class_name: "ProcessRun",
    foreign_key: :origin_message_id,
    dependent: :restrict_with_exception,
    inverse_of: :origin_message

  validates :content, presence: true
  validates :variant_index,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 },
    uniqueness: { scope: [:turn_id, :slot] }
  validate :transcript_bearing_subclass_only
  validate :conversation_installation_match
  validate :turn_installation_match
  validate :turn_conversation_match
  validate :source_input_message_rules

  def fork_point?
    direct_anchor? || source_input_of_anchored_output?
  end

  private

  def direct_anchor?
    Conversation.where(parent_conversation_id: conversation_id, historical_anchor_message_id: id).exists?
  end

  def source_input_of_anchored_output?
    return false unless input?

    Conversation.joins(
      "INNER JOIN messages anchor_messages ON anchor_messages.id = conversations.historical_anchor_message_id"
    ).where(
      parent_conversation_id: conversation_id,
      anchor_messages: { source_input_message_id: id }
    ).exists?
  end

  def transcript_bearing_subclass_only
    return if TRANSCRIPT_BEARING_TYPES.include?(self.class.name)

    errors.add(:type, "must be a transcript-bearing subclass")
  end

  def conversation_installation_match
    return if conversation.blank?
    return if conversation.installation_id == installation_id

    errors.add(:conversation, "must belong to the same installation")
  end

  def turn_installation_match
    return if turn.blank?
    return if turn.installation_id == installation_id

    errors.add(:turn, "must belong to the same installation")
  end

  def turn_conversation_match
    return if turn.blank? || conversation.blank?
    return if turn.conversation_id == conversation_id

    errors.add(:conversation, "must match the turn conversation")
  end

  def source_input_message_rules
    if input?
      errors.add(:source_input_message, "must be blank for input messages") if source_input_message.present?
      return
    end

    return if source_input_message.blank?
    return if source_input_message.turn_id == turn_id && source_input_message.input?

    errors.add(:source_input_message, "must be an input message from the same turn")
  end
end
