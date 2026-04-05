class WorkflowRun < ApplicationRecord
  include HasPublicId

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
      subagent_barrier: "subagent_barrier",
      agent_unavailable: "agent_unavailable",
      manual_recovery_required: "manual_recovery_required",
      policy_gate: "policy_gate",
      retryable_failure: "retryable_failure",
      external_dependency_blocked: "external_dependency_blocked",
    },
    validate: { allow_nil: true }
  enum :cancellation_reason_kind,
    {
      conversation_deleted: "conversation_deleted",
      conversation_archived: "conversation_archived",
      turn_interrupted: "turn_interrupted",
    },
    validate: { allow_nil: true }
  enum :resume_policy,
    {
      re_enter_agent: "re_enter_agent",
    },
    validate: { allow_nil: true }

  belongs_to :installation
  belongs_to :conversation
  belongs_to :turn
  belongs_to :wait_snapshot_document, class_name: "JsonDocument", optional: true

  has_many :workflow_nodes, dependent: :restrict_with_exception
  has_many :workflow_edges, dependent: :restrict_with_exception
  has_many :workflow_artifacts, dependent: :restrict_with_exception
  has_many :workflow_node_events, dependent: :restrict_with_exception
  has_many :human_interaction_requests, dependent: :restrict_with_exception
  has_many :process_runs, through: :workflow_nodes
  has_many :execution_leases, dependent: :restrict_with_exception

  delegate :execution_snapshot, to: :turn, allow_nil: true
  delegate :workspace, to: :conversation, allow_nil: true
  delegate :normalized_selector,
    :resolved_provider_handle,
    :resolved_model_ref,
    :resolved_role_name,
    to: :turn,
    allow_nil: true
  delegate :identity,
    :task,
    :conversation_projection,
    :capability_projection,
    :provider_context,
    :runtime_context,
    :model_context,
    :provider_execution,
    :budget_hints,
    :attachment_manifest,
    :model_input_attachments,
    :attachment_diagnostics,
    :context_imports,
    to: :execution_snapshot,
    allow_nil: true

  def execution_identity
    execution_snapshot&.identity
  end

  def workspace_id
    workspace&.id
  end

  def feature_policy_snapshot
    turn&.feature_policy_snapshot || {}
  end

  def feature_enabled?(feature_id)
    Array(feature_policy_snapshot["enabled_feature_ids"]).include?(feature_id.to_s)
  end

  validate :wait_reason_payload_must_be_hash
  validate :conversation_installation_match
  validate :turn_installation_match
  validate :turn_conversation_match
  validate :one_active_workflow_per_conversation
  validate :wait_state_consistency
  validate :cancellation_request_pairing
  validate :recovery_state_consistency
  validate :resume_state_consistency

  validates :turn_id, uniqueness: true

  def waiting_on_agent_unavailable?
    waiting? && wait_reason_kind == "agent_unavailable"
  end

  def waiting_on_subagent_barrier?
    waiting? && wait_reason_kind == "subagent_barrier"
  end

  def paused_agent_unavailable?
    waiting? &&
      wait_reason_kind == "manual_recovery_required" &&
      recovery_state == "paused_agent_unavailable"
  end

  def pause_requested?
    waiting? &&
      wait_reason_kind == "manual_recovery_required" &&
      recovery_state == Workflows::TurnPauseState::RECOVERY_STATE_PENDING
  end

  def paused_turn?
    waiting? &&
      wait_reason_kind == "manual_recovery_required" &&
      recovery_state == Workflows::TurnPauseState::RECOVERY_STATE_PAUSED
  end

  def paused_wait_snapshot
    WorkflowWaitSnapshot.from_workflow_run(self)
  end

  def recovery_agent_task_run
    return if recovery_agent_task_run_public_id.blank?

    AgentTaskRun.find_by(
      workflow_run: self,
      public_id: recovery_agent_task_run_public_id
    )
  end

  def resume_yielding_workflow_node
    return if resume_yielding_node_key.blank?

    workflow_nodes.find_by(node_key: resume_yielding_node_key)
  end

  def resume_metadata
    successor = {
      "node_key" => resume_successor_node_key,
      "node_type" => resume_successor_node_type,
    }.compact

    {
      "batch_id" => resume_batch_id,
      "yielding_node_key" => resume_yielding_node_key,
      "successor" => successor.presence,
    }.compact
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
      errors.add(:recovery_state, "must be blank when workflow run is ready") if recovery_state.present?
      errors.add(:recovery_reason, "must be blank when workflow run is ready") if recovery_reason.present?
      errors.add(:recovery_drift_reason, "must be blank when workflow run is ready") if recovery_drift_reason.present?
      errors.add(:recovery_agent_task_run_public_id, "must be blank when workflow run is ready") if recovery_agent_task_run_public_id.present?
      errors.add(:wait_snapshot_document, "must be blank when workflow run is ready") if wait_snapshot_document_id.present?
      errors.add(:waiting_since_at, "must be blank when workflow run is ready") if waiting_since_at.present?
      errors.add(:blocking_resource_type, "must be blank when workflow run is ready") if blocking_resource_type.present?
      errors.add(:blocking_resource_id, "must be blank when workflow run is ready") if blocking_resource_id.present?
    end

    if blocking_resource_type.present? ^ blocking_resource_id.present?
      errors.add(:blocking_resource_id, "must be paired with blocking resource type")
    end
  end

  def recovery_state_consistency
    recovery_fields_present = recovery_state.present? ||
      recovery_reason.present? ||
      recovery_drift_reason.present? ||
      recovery_agent_task_run_public_id.present? ||
      wait_snapshot_document_id.present?
    return unless recovery_fields_present

    return if waiting? && wait_reason_kind.in?(%w[manual_recovery_required agent_unavailable])

    errors.add(:recovery_state, "must belong to a recovery wait state")
  end

  def resume_state_consistency
    resume_fields_present = resume_batch_id.present? ||
      resume_yielding_node_key.present? ||
      resume_successor_node_key.present? ||
      resume_successor_node_type.present?

    if resume_policy.blank?
      errors.add(:resume_policy, "must exist when resume state is present") if resume_fields_present
      return
    end

    if resume_successor_node_key.present? ^ resume_successor_node_type.present?
      errors.add(:resume_successor_node_type, "must be paired with resume successor node key")
    end
  end

  def cancellation_request_pairing
    if cancellation_reason_kind.present? && cancellation_requested_at.blank?
      errors.add(:cancellation_requested_at, "must exist when cancellation reason is present")
    end

    if cancellation_reason_kind.blank? && cancellation_requested_at.present?
      errors.add(:cancellation_reason_kind, "must exist when cancellation has been requested")
    end
  end
end
