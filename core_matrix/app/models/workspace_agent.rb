class WorkspaceAgent < ApplicationRecord
  include HasPublicId

  LIFECYCLE_STATES = %w[active revoked retired].freeze
  CAPABILITY_POLICY_KEYS = %w[disabled_capabilities].freeze
  SETTINGS_PAYLOAD_KEYS = %w[
    interactive_profile_key
    default_subagent_profile_key
    enabled_subagent_profile_keys
    delegation_mode
    max_concurrent_subagents
    max_subagent_depth
    allow_nested_subagents
    default_subagent_model_selector_hint
  ].freeze
  DELEGATION_MODES = %w[allow prefer].freeze

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
  validate :settings_payload_must_be_hash
  validate :settings_payload_supported
  validate :immutable_after_terminal_lifecycle_state, on: :update
  validate :terminal_transition_only_allows_terminal_metadata, on: :update

  before_validation :normalize_capability_policy_payload
  before_validation :normalize_global_instructions
  before_validation :normalize_settings_payload

  after_commit :lock_conversations_after_revocation, on: %i[create update]

  def active? = lifecycle_state == "active"

  def revoked? = lifecycle_state == "revoked"

  def retired? = lifecycle_state == "retired"

  def disabled_capabilities
    WorkspacePolicies::Capabilities.normalize_capabilities(
      capability_policy_payload.is_a?(Hash) ? capability_policy_payload["disabled_capabilities"] : nil
    )
  end

  def interactive_profile_key_override
    normalized_settings_payload["interactive_profile_key"]
  end

  def default_subagent_profile_key_override
    normalized_settings_payload["default_subagent_profile_key"]
  end

  def enabled_subagent_profile_keys
    Array(normalized_settings_payload["enabled_subagent_profile_keys"])
  end

  def delegation_mode_override
    normalized_settings_payload["delegation_mode"]
  end

  def max_concurrent_subagents_override
    normalized_settings_payload["max_concurrent_subagents"]
  end

  def max_subagent_depth_override
    normalized_settings_payload["max_subagent_depth"]
  end

  def allow_nested_subagents_override
    normalized_settings_payload["allow_nested_subagents"]
  end

  def default_subagent_model_selector_hint_override
    normalized_settings_payload["default_subagent_model_selector_hint"]
  end

  def profile_settings_view
    SETTINGS_PAYLOAD_KEYS.each_with_object({}) do |key, view|
      next unless normalized_settings_payload.key?(key)

      view[key] = normalized_settings_payload[key]
    end
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

  def normalize_settings_payload
    return self.settings_payload = {} if settings_payload.blank?
    return unless settings_payload.is_a?(Hash)

    normalized = settings_payload.deep_stringify_keys
    normalize_string_setting!(normalized, "interactive_profile_key")
    normalize_string_setting!(normalized, "default_subagent_profile_key")
    normalize_string_setting!(normalized, "delegation_mode")
    normalize_string_setting!(normalized, "default_subagent_model_selector_hint")
    normalize_array_setting!(normalized, "enabled_subagent_profile_keys")
    normalize_integer_setting!(normalized, "max_concurrent_subagents")
    normalize_integer_setting!(normalized, "max_subagent_depth")
    normalize_boolean_setting!(normalized, "allow_nested_subagents")
    if normalized.key?("enabled_subagent_profile_keys")
      normalized["enabled_subagent_profile_keys"] -= [current_interactive_profile_key(normalized)]
    end

    self.settings_payload = normalized.compact
  end

  def capability_policy_payload_must_be_hash
    return if capability_policy_payload.is_a?(Hash)

    errors.add(:capability_policy_payload, "must be a hash")
  end

  def settings_payload_must_be_hash
    return if settings_payload.is_a?(Hash)

    errors.add(:settings_payload, "must be a hash")
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

  def settings_payload_supported
    return unless settings_payload.is_a?(Hash)

    normalized = normalized_settings_payload
    unsupported_keys = settings_payload.deep_stringify_keys.keys - SETTINGS_PAYLOAD_KEYS
    errors.add(:settings_payload, "must only contain supported keys") if unsupported_keys.any?

    validate_string_setting(normalized, "interactive_profile_key")
    validate_string_setting(normalized, "default_subagent_profile_key")
    validate_string_setting(normalized, "default_subagent_model_selector_hint")

    if normalized.key?("enabled_subagent_profile_keys") && !normalized["enabled_subagent_profile_keys"].is_a?(Array)
      errors.add(:settings_payload, "enabled_subagent_profile_keys must be an array")
    end

    if normalized.key?("delegation_mode") && !DELEGATION_MODES.include?(normalized["delegation_mode"])
      errors.add(:settings_payload, "delegation_mode must be one of: #{DELEGATION_MODES.join(", ")}")
    end

    validate_positive_integer_setting(normalized, "max_concurrent_subagents")
    validate_positive_integer_setting(normalized, "max_subagent_depth")

    if normalized.key?("allow_nested_subagents") && ![true, false].include?(normalized["allow_nested_subagents"])
      errors.add(:settings_payload, "allow_nested_subagents must be a boolean")
    end

    validate_profile_key_membership(normalized)
    validate_default_subagent_membership(normalized)
    validate_enabled_subagent_profiles_exclude_interactive(normalized)
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

  def normalized_settings_payload
    settings_payload.is_a?(Hash) ? settings_payload.deep_stringify_keys : {}
  end

  def normalize_string_setting!(normalized, key)
    normalized[key] = normalized[key].to_s.strip.presence if normalized.key?(key)
  end

  def normalize_array_setting!(normalized, key)
    return unless normalized.key?(key)

    normalized[key] = Array(normalized[key]).map { |value| value.to_s.strip.presence }.compact.uniq.sort
  end

  def normalize_integer_setting!(normalized, key)
    return unless normalized.key?(key)

    value = normalized[key]
    return normalized[key] = nil if value.respond_to?(:strip) && value.strip.empty?

    converted = Integer(value, exception: false)
    normalized[key] = converted.nil? ? value : converted
  end

  def normalize_boolean_setting!(normalized, key)
    return unless normalized.key?(key)

    normalized[key] = normalized[key] if [true, false].include?(normalized[key])
  end

  def validate_string_setting(normalized, key)
    return unless normalized.key?(key)
    return if normalized[key].nil? || normalized[key].is_a?(String)

    errors.add(:settings_payload, "#{key} must be a string")
  end

  def validate_positive_integer_setting(normalized, key)
    return unless normalized.key?(key)
    return if normalized[key].is_a?(Integer) && normalized[key].positive?

    errors.add(:settings_payload, "#{key} must be a positive integer")
  end

  def validate_profile_key_membership(normalized)
    available_profile_keys = current_profile_policy.keys
    return if available_profile_keys.empty?

    %w[interactive_profile_key default_subagent_profile_key].each do |key|
      next unless normalized[key].present?
      next if available_profile_keys.include?(normalized[key])

      errors.add(:settings_payload, "#{key} must reference a known profile key")
    end

    unknown_enabled_keys = Array(normalized["enabled_subagent_profile_keys"]) - available_profile_keys
    errors.add(:settings_payload, "enabled_subagent_profile_keys must reference known profile keys") if unknown_enabled_keys.any?
  end

  def validate_default_subagent_membership(normalized)
    return unless normalized["default_subagent_profile_key"].present?
    return unless normalized.key?("enabled_subagent_profile_keys")
    return if Array(normalized["enabled_subagent_profile_keys"]).include?(normalized["default_subagent_profile_key"])

    errors.add(:settings_payload, "default_subagent_profile_key must be included in enabled_subagent_profile_keys")
  end

  def validate_enabled_subagent_profiles_exclude_interactive(normalized)
    return unless normalized.key?("enabled_subagent_profile_keys")

    interactive_profile_key = current_interactive_profile_key(normalized)
    return if interactive_profile_key.blank?
    return unless Array(normalized["enabled_subagent_profile_keys"]).include?(interactive_profile_key)

    errors.add(:settings_payload, "enabled_subagent_profile_keys must not include the interactive profile")
  end

  def current_interactive_profile_key(normalized)
    normalized["interactive_profile_key"].presence ||
      current_default_canonical_config.dig("interactive", "profile").presence ||
      current_default_canonical_config.dig("interactive", "default_profile_key").presence ||
      "main"
  end

  def current_default_canonical_config
    current_definition_version = agent&.current_agent_definition_version || agent&.published_agent_definition_version
    current_definition_version&.default_canonical_config || {}
  end

  def current_profile_policy
    current_definition_version = agent&.current_agent_definition_version || agent&.published_agent_definition_version
    current_definition_version&.profile_policy || {}
  end
end
