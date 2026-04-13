class HumanInteractionRequest < ApplicationRecord
  include HasPublicId
  include DetailBackedJsonFields

  STI_TYPES = %w[ApprovalRequest HumanFormRequest HumanTaskRequest].freeze
  RESOLUTION_KINDS = %w[approved denied submitted completed canceled timed_out].freeze

  enum :lifecycle_state,
    {
      open: "open",
      resolved: "resolved",
      canceled: "canceled",
      timed_out: "timed_out",
    },
    validate: true

  belongs_to :installation
  belongs_to :user
  belongs_to :workspace
  belongs_to :agent
  belongs_to :workflow_run
  belongs_to :workflow_node
  belongs_to :conversation
  belongs_to :turn
  has_one :human_interaction_request_detail, dependent: :destroy, autosave: true, inverse_of: :human_interaction_request

  detail_backed_json_fields :human_interaction_request_detail, :request_payload, :result_payload

  validates :type, presence: true
  validate :supported_subtype
  validate :request_payload_must_be_hash
  validate :result_payload_must_be_hash
  validate :user_installation_match
  validate :workspace_installation_match
  validate :agent_installation_match
  validate :workflow_run_installation_match
  validate :workflow_node_installation_match
  validate :conversation_installation_match
  validate :turn_installation_match
  validate :workflow_node_workflow_run_match
  validate :workflow_run_turn_match
  validate :workflow_run_conversation_match
  validate :workflow_run_owner_context_match
  validate :resolution_kind_inclusion
  validate :resolution_state_consistency

  def self.type_names = STI_TYPES

  def expired?
    expires_at.present? && expires_at <= Time.current
  end

  def resolve!(resolution_kind:, result_payload:, resolved_at: Time.current)
    update!(
      lifecycle_state: "resolved",
      resolution_kind: resolution_kind,
      result_payload: result_payload,
      resolved_at: resolved_at
    )
  end

  def time_out!(result_payload: {}, resolved_at: Time.current)
    update!(
      lifecycle_state: "timed_out",
      resolution_kind: "timed_out",
      result_payload: result_payload,
      resolved_at: resolved_at
    )
  end

  private

  def supported_subtype
    return if self.class.name.in?(STI_TYPES)

    errors.add(:type, "must be a supported human interaction request subtype")
  end

  def request_payload_must_be_hash
    errors.add(:request_payload, "must be a hash") unless request_payload.is_a?(Hash)
  end

  def user_installation_match
    return if user.blank?
    return if user.installation_id == installation_id

    errors.add(:user, "must belong to the same installation")
  end

  def workspace_installation_match
    return if workspace.blank?
    return if workspace.installation_id == installation_id

    errors.add(:workspace, "must belong to the same installation")
  end

  def agent_installation_match
    return if agent.blank?
    return if agent.installation_id == installation_id

    errors.add(:agent, "must belong to the same installation")
  end

  def result_payload_must_be_hash
    errors.add(:result_payload, "must be a hash") unless result_payload.is_a?(Hash)
  end

  def workflow_run_installation_match
    return if workflow_run.blank?
    return if workflow_run.installation_id == installation_id

    errors.add(:workflow_run, "must belong to the same installation")
  end

  def workflow_node_installation_match
    return if workflow_node.blank?
    return if workflow_node.installation_id == installation_id

    errors.add(:workflow_node, "must belong to the same installation")
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

  def workflow_node_workflow_run_match
    return if workflow_node.blank? || workflow_run.blank?
    return if workflow_node.workflow_run_id == workflow_run_id

    errors.add(:workflow_node, "must belong to the same workflow run")
  end

  def workflow_run_turn_match
    return if workflow_run.blank? || turn.blank?
    return if workflow_run.turn_id == turn_id

    errors.add(:turn, "must match the workflow run turn")
  end

  def workflow_run_conversation_match
    return if workflow_run.blank? || conversation.blank?
    return if workflow_run.conversation_id == conversation_id

    errors.add(:conversation, "must match the workflow run conversation")
  end

  def workflow_run_owner_context_match
    return if workflow_run.blank?

    errors.add(:user, "must match the workflow run user") if user.present? && workflow_run.user_id != user_id
    errors.add(:workspace, "must match the workflow run workspace") if workspace.present? && workflow_run.workspace_id != workspace_id
    errors.add(:agent, "must match the workflow run agent") if agent.present? && workflow_run.agent_id != agent_id
  end

  def resolution_state_consistency
    if open?
      errors.add(:resolution_kind, "must be blank while request is open") if resolution_kind.present?
      errors.add(:resolved_at, "must be blank while request is open") if resolved_at.present?
      errors.add(:result_payload, "must be empty while request is open") if result_payload.present?
      return
    end

    errors.add(:resolution_kind, "must exist once request leaves the open state") if resolution_kind.blank?
    errors.add(:resolved_at, "must exist once request leaves the open state") if resolved_at.blank?
  end

  def resolution_kind_inclusion
    return if resolution_kind.blank?
    return if resolution_kind.in?(RESOLUTION_KINDS)

    errors.add(:resolution_kind, "must be a supported resolution kind")
  end
end
