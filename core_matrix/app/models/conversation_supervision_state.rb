class ConversationSupervisionState < ApplicationRecord
  include HasPublicId
  include DataLifecycle

  OVERALL_STATES = %w[idle queued running waiting blocked completed failed interrupted canceled].freeze
  LAST_TERMINAL_STATES = %w[completed failed interrupted canceled].freeze
  BOARD_LANES = %w[idle queued active waiting blocked handoff done failed].freeze

  data_lifecycle_kind! :recomputable

  belongs_to :installation
  belongs_to :target_conversation, class_name: "Conversation"

  validates :overall_state, inclusion: { in: OVERALL_STATES }
  validates :last_terminal_state, inclusion: { in: LAST_TERMINAL_STATES }, allow_nil: true
  validates :board_lane, inclusion: { in: BOARD_LANES }
  validates :target_conversation, uniqueness: true
  validate :target_conversation_installation_match
  validate :board_badges_must_be_array
  validate :counter_fields_must_be_non_negative
  validate :status_payload_must_be_hash

  private

  def target_conversation_installation_match
    return if target_conversation.blank?
    return if target_conversation.installation_id == installation_id

    errors.add(:target_conversation, "must belong to the same installation")
  end

  def status_payload_must_be_hash
    errors.add(:status_payload, "must be a hash") unless status_payload.is_a?(Hash)
  end

  def board_badges_must_be_array
    errors.add(:board_badges, "must be an array") unless board_badges.is_a?(Array)
  end

  def counter_fields_must_be_non_negative
    %i[active_plan_item_count completed_plan_item_count active_subagent_count].each do |field_name|
      value = public_send(field_name)
      next if value.is_a?(Integer) && value >= 0

      errors.add(field_name, "must be a non-negative integer")
    end
  end
end
