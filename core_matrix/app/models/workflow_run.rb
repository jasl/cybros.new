class WorkflowRun < ApplicationRecord
  enum :lifecycle_state,
    {
      active: "active",
      completed: "completed",
      failed: "failed",
      canceled: "canceled",
    },
    validate: true
  enum :wait_state,
    {
      ready: "ready",
      waiting: "waiting",
    },
    validate: true
  enum :wait_reason_kind,
    {
      human_interaction: "human_interaction",
      agent_unavailable: "agent_unavailable",
      manual_recovery_required: "manual_recovery_required",
      policy_gate: "policy_gate",
    },
    validate: { allow_nil: true }

  belongs_to :installation
  belongs_to :conversation
  belongs_to :turn

  has_many :workflow_nodes, dependent: :restrict_with_exception
  has_many :workflow_edges, dependent: :restrict_with_exception
  has_many :workflow_artifacts, dependent: :restrict_with_exception
  has_many :workflow_node_events, dependent: :restrict_with_exception
  has_many :human_interaction_requests, dependent: :restrict_with_exception
  has_many :process_runs, through: :workflow_nodes
  has_many :subagent_runs, dependent: :restrict_with_exception
  has_many :execution_leases, dependent: :restrict_with_exception

  delegate :normalized_selector,
    :resolved_provider_handle,
    :resolved_model_ref,
    :resolved_role_name,
    :execution_identity,
    :attachment_manifest,
    :runtime_attachment_manifest,
    :model_input_attachments,
    :attachment_diagnostics,
    to: :turn,
    allow_nil: true

  validates :turn_id, uniqueness: true
  validate :wait_reason_payload_must_be_hash
  validate :conversation_installation_match
  validate :turn_installation_match
  validate :turn_conversation_match
  validate :one_active_workflow_per_conversation
  validate :wait_state_consistency

  def waiting_on_agent_unavailable?
    waiting? && wait_reason_kind == "agent_unavailable"
  end

  def paused_agent_unavailable?
    waiting? &&
      wait_reason_kind == "manual_recovery_required" &&
      wait_reason_payload["recovery_state"] == "paused_agent_unavailable"
  end

  private

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

  def one_active_workflow_per_conversation
    return unless active?

    existing_active = self.class
      .where(conversation_id: conversation_id, lifecycle_state: "active")
      .where.not(id: id)
      .exists?
    return unless existing_active

    errors.add(:conversation, "already has an active workflow")
  end

  def wait_reason_payload_must_be_hash
    errors.add(:wait_reason_payload, "must be a hash") unless wait_reason_payload.is_a?(Hash)
  end

  def wait_state_consistency
    if waiting?
      errors.add(:wait_reason_kind, "must exist when workflow run is waiting") if wait_reason_kind.blank?
      errors.add(:waiting_since_at, "must exist when workflow run is waiting") if waiting_since_at.blank?
    else
      errors.add(:wait_reason_payload, "must be empty when workflow run is ready") if wait_reason_payload.present?
      errors.add(:wait_reason_kind, "must be blank when workflow run is ready") if wait_reason_kind.present?
      errors.add(:waiting_since_at, "must be blank when workflow run is ready") if waiting_since_at.present?
      errors.add(:blocking_resource_type, "must be blank when workflow run is ready") if blocking_resource_type.present?
      errors.add(:blocking_resource_id, "must be blank when workflow run is ready") if blocking_resource_id.present?
    end

    if blocking_resource_type.present? ^ blocking_resource_id.present?
      errors.add(:blocking_resource_id, "must be paired with blocking resource type")
    end
  end
end
