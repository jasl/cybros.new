class WorkflowNode < ApplicationRecord
  include HasPublicId

  NORMALIZED_METADATA_KEYS = %w[
    blocking
    blocked_retry_state
    human_interaction_request_id
    prior_tool_node_keys
    provider_round_index
    subagent_agent_task_run_id
    subagent_conversation_id
    subagent_connection_id
    subagent_turn_id
    subagent_workflow_run_id
    transcript_side_effect_committed
  ].freeze

  attribute :lifecycle_state, :string

  enum :decision_source,
    {
      llm: "llm",
      agent: "agent",
      system: "system",
      user: "user",
    },
    validate: true
  enum :lifecycle_state,
    {
      pending: "pending",
      queued: "queued",
      running: "running",
      waiting: "waiting",
      completed: "completed",
      failed: "failed",
      canceled: "canceled",
    },
    validate: true
  enum :presentation_policy,
    {
      internal_only: "internal_only",
      ops_trackable: "ops_trackable",
      user_projectable: "user_projectable",
    },
    validate: true

  belongs_to :installation
  belongs_to :workflow_run
  belongs_to :workspace
  belongs_to :conversation
  belongs_to :turn
  belongs_to :yielding_workflow_node, class_name: "WorkflowNode", optional: true
  belongs_to :opened_human_interaction_request, class_name: "HumanInteractionRequest", optional: true
  belongs_to :spawned_subagent_connection, class_name: "SubagentConnection", optional: true
  belongs_to :tool_call_document, class_name: "JsonDocument", optional: true

  has_many :outgoing_edges,
    class_name: "WorkflowEdge",
    foreign_key: :from_node_id,
    dependent: :restrict_with_exception,
    inverse_of: :from_node
  has_many :incoming_edges,
    class_name: "WorkflowEdge",
    foreign_key: :to_node_id,
    dependent: :restrict_with_exception,
    inverse_of: :to_node
  has_many :workflow_artifacts, dependent: :restrict_with_exception
  has_many :workflow_node_events, dependent: :restrict_with_exception
  has_many :human_interaction_requests, dependent: :restrict_with_exception
  has_many :tool_bindings, dependent: :restrict_with_exception
  has_many :tool_invocations, dependent: :restrict_with_exception
  has_many :command_runs, dependent: :restrict_with_exception
  has_many :process_runs, dependent: :restrict_with_exception
  has_many :execution_leases, dependent: :restrict_with_exception
  has_many :yielded_workflow_nodes,
    class_name: "WorkflowNode",
    foreign_key: :yielding_workflow_node_id,
    dependent: :nullify,
    inverse_of: :yielding_workflow_node

  before_validation :default_projection_fields_from_workflow_run

  validates :node_key, presence: true, uniqueness: { scope: :workflow_run_id }
  validates :node_type, presence: true
  validates :ordinal,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 },
    uniqueness: { scope: :workflow_run_id }
  validates :stage_index,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 },
    allow_nil: true
  validates :stage_position,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 },
    allow_nil: true
  validate :workflow_run_installation_match
  validate :workspace_installation_match
  validate :conversation_installation_match
  validate :turn_installation_match
  validate :tool_call_document_installation_match
  validate :opened_human_interaction_request_installation_match
  validate :spawned_subagent_connection_installation_match
  validate :workflow_projection_match
  validate :yielding_workflow_integrity
  validate :execution_timestamps_consistency
  validate :metadata_must_be_hash
  validate :metadata_must_not_duplicate_structured_state
  validate :intent_state_consistency
  validate :provider_round_state_consistency
  validate :blocked_retry_state_consistency

  def terminal?
    completed? || failed? || canceled?
  end

  def tool_call_payload
    tool_call_document&.payload
  end

  def intent_payload
    return {} if intent_batch_id.blank? || intent_id.blank? || yielding_workflow_node.blank?

    @intent_payload ||= begin
      manifest = workflow_run.workflow_artifacts.find_by(
        workflow_node: yielding_workflow_node,
        artifact_kind: "intent_batch_manifest",
        artifact_key: intent_batch_id
      )
      manifest_payload = manifest&.payload || {}

      Array(manifest_payload["stages"])
        .flat_map { |stage| Array(stage["intents"]) }
        .find { |intent| intent["intent_id"] == intent_id }
        &.fetch("payload", {}) || {}
    end
  end

  def blocked_retry_state
    return if blocked_retry_failure_kind.blank? || blocked_retry_attempt_no.blank?

    {
      "failure_kind" => blocked_retry_failure_kind,
      "attempt_no" => blocked_retry_attempt_no,
    }
  end

  private

  def default_projection_fields_from_workflow_run
    return if workflow_run.blank?

    self.workspace ||= workflow_run.workspace
    self.conversation ||= workflow_run.conversation
    self.turn ||= workflow_run.turn
  end

  def workflow_run_installation_match
    return if workflow_run.blank?
    return if workflow_run.installation_id == installation_id

    errors.add(:workflow_run, "must belong to the same installation")
  end

  def workspace_installation_match
    return if workspace.blank?
    return if workspace.installation_id == installation_id

    errors.add(:workspace, "must belong to the same installation")
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

  def tool_call_document_installation_match
    return if tool_call_document.blank?
    return if tool_call_document.installation_id == installation_id

    errors.add(:tool_call_document, "must belong to the same installation")
  end

  def opened_human_interaction_request_installation_match
    return if opened_human_interaction_request.blank?
    return if opened_human_interaction_request.installation_id == installation_id

    errors.add(:opened_human_interaction_request, "must belong to the same installation")
  end

  def spawned_subagent_connection_installation_match
    return if spawned_subagent_connection.blank?
    return if spawned_subagent_connection.installation_id == installation_id

    errors.add(:spawned_subagent_connection, "must belong to the same installation")
  end

  def workflow_projection_match
    return if workflow_run.blank?

    if workspace.present? && workflow_run.workspace_id != workspace_id
      errors.add(:workspace, "must match the workflow run workspace")
    end
    if conversation.present? && workflow_run.conversation_id != conversation_id
      errors.add(:conversation, "must match the workflow run conversation")
    end
    if turn.present? && workflow_run.turn_id != turn_id
      errors.add(:turn, "must match the workflow run turn")
    end
    if opened_human_interaction_request.present? && opened_human_interaction_request.workflow_run_id != workflow_run_id
      errors.add(:opened_human_interaction_request, "must belong to the same workflow run")
    end
    if spawned_subagent_connection.present? && spawned_subagent_connection.owner_conversation_id != conversation_id
      errors.add(:spawned_subagent_connection, "must belong to the same owner conversation")
    end
  end

  def yielding_workflow_integrity
    return if yielding_workflow_node.blank?
    return if yielding_workflow_node.workflow_run_id == workflow_run_id

    errors.add(:yielding_workflow_node, "must belong to the same workflow run")
  end

  def execution_timestamps_consistency
    if pending? || queued?
      errors.add(:started_at, "must be blank before execution starts") if started_at.present?
      errors.add(:finished_at, "must be blank before execution finishes") if finished_at.present?
    end

    if running? || waiting?
      errors.add(:started_at, "must exist while execution is running") if started_at.blank?
      errors.add(:finished_at, "must be blank while execution is running") if finished_at.present?
    end

    if terminal?
      errors.add(:finished_at, "must exist when execution has finished") if finished_at.blank?
    end

    if completed? || failed?
      errors.add(:started_at, "must exist when execution has finished") if started_at.blank?
    end

    return if started_at.blank? || finished_at.blank?
    return unless finished_at < started_at

    errors.add(:finished_at, "must be after started_at")
  end

  def metadata_must_be_hash
    errors.add(:metadata, "must be a hash") unless metadata.is_a?(Hash)
  end

  def metadata_must_not_duplicate_structured_state
    return unless metadata.is_a?(Hash)

    duplicated_keys = NORMALIZED_METADATA_KEYS.select { |key| metadata.key?(key) }
    return if duplicated_keys.empty?

    errors.add(:metadata, "must not inline normalized workflow node state: #{duplicated_keys.join(", ")}")
  end

  def intent_state_consistency
    if [intent_id, intent_batch_id].any?(&:present?) && intent_kind.blank?
      errors.add(:intent_kind, "must be present when intent tracking columns are populated")
    end

    if intent_batch_id.present? ^ intent_id.present?
      errors.add(:intent_batch_id, "must be paired with intent_id")
    end

    return unless metadata.is_a?(Hash)
    return if intent_kind.blank?

    %w[payload intent_kind idempotency_key requirement conflict_scope].each do |key|
      errors.add(:metadata, "must not inline #{key} for intent-backed workflow nodes") if metadata.key?(key)
    end
  end

  def provider_round_state_consistency
    return if provider_round_index.blank? && prior_tool_node_keys.blank?

    errors.add(:provider_round_index, "must be present when prior_tool_node_keys are tracked") if provider_round_index.blank?
    unless prior_tool_node_keys.is_a?(Array) && prior_tool_node_keys.all? { |value| value.is_a?(String) }
      errors.add(:prior_tool_node_keys, "must be an array of strings")
    end
  end

  def blocked_retry_state_consistency
    return if blocked_retry_failure_kind.blank? && blocked_retry_attempt_no.blank?
    return if blocked_retry_failure_kind.present? && blocked_retry_attempt_no.present?

    errors.add(:blocked_retry_failure_kind, "must be paired with blocked_retry_attempt_no")
  end
end
