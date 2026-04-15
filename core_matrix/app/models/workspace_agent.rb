class WorkspaceAgent < ApplicationRecord
  include HasPublicId

  LIFECYCLE_STATES = %w[active revoked retired].freeze
  CAPABILITY_POLICY_KEYS = %w[disabled_capabilities].freeze

  belongs_to :installation
  belongs_to :workspace
  belongs_to :agent
  belongs_to :default_execution_runtime, class_name: "ExecutionRuntime", optional: true

  has_many :conversations, dependent: :restrict_with_exception
  has_many :ingress_bindings, dependent: :restrict_with_exception

  validates :lifecycle_state, presence: true, inclusion: { in: LIFECYCLE_STATES }
  validate :workspace_installation_match
  validate :agent_installation_match
  validate :default_execution_runtime_installation_match
  validate :single_active_mount
  validate :global_instructions_must_be_string
  validate :capability_policy_payload_must_be_hash
  validate :capability_policy_payload_supported
  validate :immutable_after_terminal_lifecycle_state, on: :update
  validate :terminal_transition_only_allows_terminal_metadata, on: :update

  before_validation :normalize_capability_policy_payload
  before_validation :normalize_global_instructions

  after_commit :lock_conversations_after_revocation, on: %i[create update]

  def active? = lifecycle_state == "active"

  def revoked? = lifecycle_state == "revoked"

  def retired? = lifecycle_state == "retired"

  def disabled_capabilities
    WorkspacePolicies::Capabilities.normalize_capabilities(
      capability_policy_payload.is_a?(Hash) ? capability_policy_payload["disabled_capabilities"] : nil
    )
  end

  private

  def normalize_capability_policy_payload
    return self.capability_policy_payload = {} if capability_policy_payload.blank?
    return unless capability_policy_payload.is_a?(Hash)

    normalized = capability_policy_payload.deep_stringify_keys
    if normalized["disabled_capabilities"].is_a?(Array)
      normalized["disabled_capabilities"] = WorkspacePolicies::Capabilities.normalize_capabilities(normalized["disabled_capabilities"])
    end

    self.capability_policy_payload = normalized
  end

  def normalize_global_instructions
    self.global_instructions = global_instructions.presence
  end

  def capability_policy_payload_must_be_hash
    return if capability_policy_payload.is_a?(Hash)

    errors.add(:capability_policy_payload, "must be a hash")
  end

  def global_instructions_must_be_string
    return if global_instructions.nil? || global_instructions.is_a?(String)

    errors.add(:global_instructions, "must be a string")
  end

  def capability_policy_payload_supported
    return unless capability_policy_payload.is_a?(Hash)

    normalized = capability_policy_payload.deep_stringify_keys
    unsupported_keys = normalized.keys - CAPABILITY_POLICY_KEYS
    errors.add(:capability_policy_payload, "must only contain supported keys") if unsupported_keys.any?

    if normalized.key?("disabled_capabilities") && !normalized["disabled_capabilities"].is_a?(Array)
      errors.add(:capability_policy_payload, "disabled_capabilities must be an array")
    end
  end

  def immutable_after_terminal_lifecycle_state
    previous_state = lifecycle_state_in_database
    return if previous_state.blank? || previous_state == "active"
    return unless changes_to_save.except("updated_at").any?

    errors.add(:base, "is immutable once revoked or retired")
  end

  def terminal_transition_only_allows_terminal_metadata
    previous_state = lifecycle_state_in_database
    return unless previous_state == "active"
    return unless lifecycle_state.in?(%w[revoked retired])

    allowed_changes = %w[lifecycle_state updated_at]
    allowed_changes.concat(%w[revoked_at revoked_reason_kind]) if lifecycle_state == "revoked"
    return if changes_to_save.except(*allowed_changes).empty?

    errors.add(:base, "cannot change policy or runtime while transitioning to a terminal state")
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

  def default_execution_runtime_installation_match
    return if default_execution_runtime.blank?
    return if default_execution_runtime.installation_id == installation_id

    errors.add(:default_execution_runtime, "must belong to the same installation")
  end

  def single_active_mount
    return unless active?

    conflicting_scope = self.class.where(
      workspace_id: workspace_id,
      agent_id: agent_id,
      lifecycle_state: "active"
    )
    conflicting_scope = conflicting_scope.where.not(id: id) if persisted?
    return unless conflicting_scope.exists?

    errors.add(:agent_id, "already has an active mount for this workspace")
  end

  def lock_conversations_after_revocation
    return unless revoked? || retired?

    conversations.where(interaction_lock_state: "mutable").update_all(
      interaction_lock_state: "locked_agent_access_revoked",
      updated_at: Time.current
    )
    ingress_bindings.where(lifecycle_state: "active").update_all(
      lifecycle_state: "disabled",
      updated_at: Time.current
    )
    ChannelConnector.where(
      installation_id: installation_id,
      ingress_binding_id: ingress_bindings.select(:id),
      lifecycle_state: "active"
    ).update_all(
      lifecycle_state: "disabled",
      updated_at: Time.current
    )
  end
end
