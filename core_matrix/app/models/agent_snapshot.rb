class AgentSnapshot < ApplicationRecord
  include HasPublicId

  METHOD_ID_PATTERN = /\A[a-z0-9_]+\z/
  TOOL_KINDS = %w[kernel_primitive agent_observation effect_intent].freeze
  RESERVED_CORE_MATRIX_PREFIX = "core_matrix__".freeze

  belongs_to :installation
  belongs_to :agent

  has_many :turns, dependent: :restrict_with_exception
  has_many :agent_connections, dependent: :restrict_with_exception
  has_many :tool_definitions, dependent: :restrict_with_exception

  validates :fingerprint, presence: true, uniqueness: { scope: :installation_id }
  validates :protocol_version, presence: true
  validates :sdk_version, presence: true
  validate :protocol_methods_must_be_array
  validate :tool_catalog_must_be_array
  validate :profile_catalog_must_be_hash
  validate :config_schema_snapshot_must_be_hash
  validate :conversation_override_schema_snapshot_must_be_hash
  validate :default_config_snapshot_must_be_hash
  validate :protocol_methods_contract_shape
  validate :tool_catalog_contract_shape
  validate :tool_catalog_reserved_prefix_policy
  validate :agent_installation_match

  def readonly?
    persisted?
  end

  def tool_named?(tool_name)
    tool_catalog.any? { |entry| entry["tool_name"] == tool_name }
  end

  def version
    capability_snapshot_version
  end

  def active_agent_connection
    AgentConnection.find_by(agent_snapshot_id: id, lifecycle_state: "active")
  end

  def most_recent_agent_connection
    AgentConnection.where(agent_snapshot_id: id).order(updated_at: :desc, created_at: :desc).first
  end

  def bootstrap_state
    return "superseded" if active_agent_connection.blank?
    return "pending" if active_agent_connection.pending?

    "active"
  end

  def health_status
    active_agent_connection&.health_status
  end

  def health_metadata
    active_agent_connection&.health_metadata || {}
  end

  def last_heartbeat_at
    active_agent_connection&.last_heartbeat_at
  end

  def last_health_check_at
    active_agent_connection&.last_health_check_at
  end

  def unavailability_reason
    active_agent_connection&.unavailability_reason
  end

  def control_activity_state
    active_agent_connection&.control_activity_state
  end

  def last_control_activity_at
    active_agent_connection&.last_control_activity_at
  end

  def realtime_link_state
    session = active_agent_connection || most_recent_agent_connection
    return nil if session.blank?

    session.realtime_link_connected? ? "connected" : "disconnected"
  end

  def auto_resume_eligible
    auto_resume_eligible?
  end

  def healthy?
    active_agent_connection&.healthy? == true
  end

  def degraded?
    active_agent_connection&.degraded? == true
  end

  def offline?
    active_agent_connection&.offline? == true
  end

  def retired?
    session = active_agent_connection || most_recent_agent_connection
    session&.retired? == true
  end

  def pending?
    active_agent_connection&.pending? == true
  end

  def capability_snapshot_version
    1
  end

  def matches_runtime_capability_contract?(runtime_capability_contract)
    contract =
      case runtime_capability_contract
      when RuntimeCapabilityContract
        runtime_capability_contract
      else
        RuntimeCapabilityContract.build(agent_snapshot: runtime_capability_contract)
      end

    comparable_contract_payload == {
      "protocol_methods" => contract.protocol_methods,
      "tool_catalog" => contract.agent_tool_catalog,
      "profile_catalog" => contract.profile_catalog,
      "config_schema_snapshot" => contract.config_schema_snapshot,
      "conversation_override_schema_snapshot" => contract.conversation_override_schema_snapshot,
      "default_config_snapshot" => contract.default_config_snapshot,
    }
  end

  def self.find_by_agent_connection_credential(plaintext)
    AgentConnection.find_by_plaintext_connection_credential(plaintext)&.agent_snapshot
  end

  def matches_agent_connection_credential?(plaintext)
    AgentConnection.find_by_plaintext_connection_credential(plaintext)&.agent_snapshot_id == id
  end

  def same_logical_agent?(other)
    other.present? && agent_id == other.agent_id
  end

  def eligible_for_scheduling?
    active_agent_connection&.scheduling_ready? == true
  end

  def auto_resume_eligible?
    active_agent_connection&.auto_resume_eligible? == true
  end

  def runtime_identity_matches?(turn)
    turn.present? &&
      turn.agent_snapshot_id == id &&
      turn.pinned_agent_snapshot_fingerprint == fingerprint
  end

  def preserves_capability_contract?(turn)
    return false if turn.blank?

    turn.execution_snapshot.capability_projection["tool_surface"] ==
      RuntimeCapabilities::ComposeForTurn.call(turn: turn.dup.tap { |copy| copy.agent_snapshot = self }).fetch("tool_catalog", [])
  end

  def comparable_contract_payload
    {
      "protocol_methods" => protocol_methods,
      "tool_catalog" => tool_catalog,
      "profile_catalog" => profile_catalog,
      "config_schema_snapshot" => config_schema_snapshot,
      "conversation_override_schema_snapshot" => conversation_override_schema_snapshot,
      "default_config_snapshot" => default_config_snapshot,
    }
  end

  private

  def agent_installation_match
    return if agent.blank?
    return if agent.installation_id == installation_id

    errors.add(:agent, "must belong to the same installation")
  end

  def protocol_methods_must_be_array
    errors.add(:protocol_methods, "must be an Array") unless protocol_methods.is_a?(Array)
  end

  def tool_catalog_must_be_array
    errors.add(:tool_catalog, "must be an Array") unless tool_catalog.is_a?(Array)
  end

  def profile_catalog_must_be_hash
    errors.add(:profile_catalog, "must be a Hash") unless profile_catalog.is_a?(Hash)
  end

  def config_schema_snapshot_must_be_hash
    errors.add(:config_schema_snapshot, "must be a Hash") unless config_schema_snapshot.is_a?(Hash)
  end

  def conversation_override_schema_snapshot_must_be_hash
    errors.add(:conversation_override_schema_snapshot, "must be a Hash") unless conversation_override_schema_snapshot.is_a?(Hash)
  end

  def default_config_snapshot_must_be_hash
    errors.add(:default_config_snapshot, "must be a Hash") unless default_config_snapshot.is_a?(Hash)
  end

  def protocol_methods_contract_shape
    return unless protocol_methods.is_a?(Array)

    protocol_methods.each do |entry|
      unless entry.is_a?(Hash) && entry["method_id"].to_s.match?(METHOD_ID_PATTERN)
        errors.add(:protocol_methods, "must contain snake_case method_id entries")
        break
      end
    end
  end

  def tool_catalog_contract_shape
    return unless tool_catalog.is_a?(Array)

    tool_catalog.each do |entry|
      unless entry.is_a?(Hash) && entry["tool_name"].to_s.match?(METHOD_ID_PATTERN)
        errors.add(:tool_catalog, "must contain snake_case tool_name entries")
        break
      end

      unless TOOL_KINDS.include?(entry["tool_kind"])
        errors.add(:tool_catalog, "must contain supported tool_kind values")
        break
      end
    end
  end

  def tool_catalog_reserved_prefix_policy
    return unless tool_catalog.is_a?(Array)

    tool_catalog.each do |entry|
      next unless entry.is_a?(Hash)
      next unless entry["tool_name"].to_s.start_with?(RESERVED_CORE_MATRIX_PREFIX)
      next if entry["implementation_source"] == "core_matrix"

      errors.add(:tool_catalog, "reserved core_matrix tool names may only be supplied by core_matrix implementations")
      break
    end
  end
end
