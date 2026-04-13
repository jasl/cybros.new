class ConversationSupervisionState < ApplicationRecord
  include HasPublicId
  include DataLifecycle
  include DetailBackedJsonFields

  OVERALL_STATES = %w[idle queued running waiting blocked completed failed interrupted canceled].freeze
  LAST_TERMINAL_STATES = %w[completed failed interrupted canceled].freeze
  BOARD_LANES = %w[idle queued active waiting blocked handoff done failed].freeze

  data_lifecycle_kind! :recomputable

  belongs_to :installation
  belongs_to :user
  belongs_to :workspace
  belongs_to :agent
  belongs_to :target_conversation, class_name: "Conversation"
  has_one :conversation_supervision_state_detail,
    dependent: :destroy,
    autosave: true,
    inverse_of: :conversation_supervision_state

  detail_backed_json_fields :conversation_supervision_state_detail, :status_payload

  validates :overall_state, inclusion: { in: OVERALL_STATES }
  validates :last_terminal_state, inclusion: { in: LAST_TERMINAL_STATES }, allow_nil: true
  validates :board_lane, inclusion: { in: BOARD_LANES }
  validates :target_conversation, uniqueness: true
  validate :target_conversation_installation_match
  validate :target_conversation_owner_context_match
  validate :board_badges_must_be_array
  validate :counter_fields_must_be_non_negative
  validate :status_payload_must_be_hash

  private

  def target_conversation_installation_match
    return if target_conversation.blank?
    return if target_conversation.installation_id == installation_id

    errors.add(:target_conversation, "must belong to the same installation")
  end

  def target_conversation_owner_context_match
    return if target_conversation.blank?

    errors.add(:user, "must match the target conversation user") if user_id.present? && target_conversation.user_id != user_id
    errors.add(:workspace, "must match the target conversation workspace") if workspace_id.present? && target_conversation.workspace_id != workspace_id
    errors.add(:agent, "must match the target conversation agent") if agent_id.present? && target_conversation.agent_id != agent_id
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
