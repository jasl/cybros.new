class AgentDefinitionVersion < ApplicationRecord
  include HasPublicId

  METHOD_ID_PATTERN = /\A[a-z0-9_]+\z/
  TOOL_KINDS = %w[kernel_primitive agent_observation effect_intent].freeze
  RESERVED_CORE_MATRIX_PREFIX = "core_matrix__".freeze

  belongs_to :installation
  belongs_to :agent
  belongs_to :protocol_methods_document, class_name: "JsonDocument"
  belongs_to :feature_contract_document, class_name: "JsonDocument"
  belongs_to :request_preparation_contract_document, class_name: "JsonDocument"
  belongs_to :tool_contract_document, class_name: "JsonDocument"
  belongs_to :profile_policy_document, class_name: "JsonDocument"
  belongs_to :canonical_config_schema_document, class_name: "JsonDocument"
  belongs_to :conversation_override_schema_document, class_name: "JsonDocument"
  belongs_to :workspace_agent_settings_schema_document, class_name: "JsonDocument"
  belongs_to :default_workspace_agent_settings_document, class_name: "JsonDocument"
  belongs_to :default_canonical_config_document, class_name: "JsonDocument"
  belongs_to :reflected_surface_document, class_name: "JsonDocument"

  has_many :turns, dependent: :restrict_with_exception
  has_many :agent_connections, dependent: :restrict_with_exception
  has_many :tool_definitions, dependent: :restrict_with_exception
  has_many :execution_contracts, dependent: :restrict_with_exception
  has_many :execution_capability_snapshots, dependent: :restrict_with_exception

  validates :definition_fingerprint, presence: true, uniqueness: { scope: :agent_id }
  validates :version, presence: true, uniqueness: { scope: :agent_id }
  validates :protocol_version, presence: true
  validates :sdk_version, presence: true
  validates :prompt_pack_ref, presence: true
  validates :prompt_pack_fingerprint, presence: true
  validates :program_manifest_fingerprint, presence: true
  validate :agent_installation_match
  validate :document_installation_match
  validate :protocol_methods_contract_shape
  validate :feature_contract_shape
  validate :request_preparation_contract_shape
  validate :tool_contract_shape
  validate :tool_contract_reserved_prefix_policy

  def readonly?
    persisted?
  end

  def protocol_methods
    payload_array(protocol_methods_document)
  end

  def fingerprint
    definition_fingerprint
  end

  def feature_contract
    payload_array(feature_contract_document)
  end

  def request_preparation_contract
    payload_hash(request_preparation_contract_document)
  end

  def tool_contract
    payload_array(tool_contract_document)
  end

  def profile_policy
    payload_hash(profile_policy_document)
  end

  def canonical_config_schema
    payload_hash(canonical_config_schema_document)
  end

  def conversation_override_schema
    payload_hash(conversation_override_schema_document)
  end

  def workspace_agent_settings_schema
    payload_hash(workspace_agent_settings_schema_document)
  end

  def default_workspace_agent_settings
    payload_hash(default_workspace_agent_settings_document)
  end

  def default_canonical_config
    payload_hash(default_canonical_config_document)
  end

  def reflected_surface
    payload_hash(reflected_surface_document)
  end

  def tool_named?(tool_name)
    tool_contract.any? { |entry| entry["tool_name"] == tool_name }
  end

  def active_agent_connection
    AgentConnection.find_by(agent_definition_version_id: id, lifecycle_state: "active")
  end

  def most_recent_agent_connection
    AgentConnection.where(agent_definition_version_id: id).order(updated_at: :desc, created_at: :desc).first
  end

  def bootstrap_state
    connection = active_agent_connection
    return "superseded" if connection.blank?
    return "pending" if connection.pending?

    "active"
  end

  def health_status
    active_agent_connection&.health_status
  end

  def health_metadata
    active_agent_connection&.health_metadata || {}
  end

  def unavailability_reason
    active_agent_connection&.unavailability_reason || most_recent_agent_connection&.unavailability_reason
  end

  def realtime_link_state
    connection = active_agent_connection || most_recent_agent_connection
    return nil if connection.blank?

    connection.realtime_link_connected? ? "connected" : "disconnected"
  end

  def eligible_for_scheduling?
    active_agent_connection&.scheduling_ready? == true
  end

  def auto_resume_eligible?
    active_agent_connection&.auto_resume_eligible? == true
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
    most_recent_agent_connection&.retired? == true
  end

  def pending?
    active_agent_connection&.pending? == true
  end

  def self.find_by_agent_connection_credential(plaintext)
    AgentConnection.find_by_plaintext_connection_credential(plaintext)&.agent_definition_version
  end

  def matches_agent_connection_credential?(plaintext)
    AgentConnection.find_by_plaintext_connection_credential(plaintext)&.agent_definition_version_id == id
  end

  def same_logical_agent?(other)
    other.present? && agent_id == other.agent_id
  end

  def runtime_identity_matches?(turn)
    return false if turn.blank?
    return false unless agent.default_execution_runtime_id == turn.execution_runtime_id
    return false unless definition_fingerprint == turn.pinned_agent_definition_fingerprint

    preserves_capability_contract?(turn)
  end

  def preserves_capability_contract?(turn)
    return false if turn.blank?

    required_projection = turn.execution_snapshot.capability_projection
    candidate_projection = recovery_capability_projection_for(turn)

    recovery_context_keys.all? do |key|
      required_projection[key] == candidate_projection[key]
    end && compatible_tool_surface?(
      required_projection.fetch("tool_surface", []),
      candidate_projection.fetch("tool_surface", [])
    )
  end

  private

  def recovery_capability_projection_for(turn)
    composer = RuntimeCapabilities::ComposeForTurn.new(turn: recovery_probe_turn_for(turn))

    {
      "tool_surface" => composer.call.fetch("tool_catalog"),
      "profile_key" => composer.current_profile_key,
      "is_subagent" => turn.conversation.subagent_connection.present?,
      "subagent_connection_id" => turn.conversation.subagent_connection&.public_id,
      "parent_subagent_connection_id" => turn.conversation.subagent_connection&.parent_subagent_connection&.public_id,
      "subagent_depth" => turn.conversation.subagent_connection&.depth,
      "owner_conversation_id" => turn.conversation.subagent_connection&.owner_conversation&.public_id,
      "subagent_policy" => deep_stringify(composer.contract.default_canonical_config.fetch("subagents", {})),
    }.compact
  end

  def recovery_probe_turn_for(turn)
    turn.dup.tap do |probe_turn|
      probe_turn.installation = turn.installation
      probe_turn.conversation = turn.conversation
      probe_turn.agent_definition_version = self
      probe_turn.execution_runtime = turn.execution_runtime
      probe_turn.execution_runtime_version = turn.execution_runtime_version
      probe_turn.agent_config_version = turn.agent_config_version
      probe_turn.agent_config_content_fingerprint = turn.agent_config_content_fingerprint
      probe_turn.resolved_config_snapshot = turn.resolved_config_snapshot.deep_dup
      probe_turn.resolved_model_selection_snapshot = turn.resolved_model_selection_snapshot.deep_dup
    end
  end

  def recovery_context_keys
    %w[
      profile_key
      is_subagent
      subagent_connection_id
      parent_subagent_connection_id
      subagent_depth
      owner_conversation_id
      subagent_policy
    ]
  end

  def compatible_tool_surface?(required_surface, candidate_surface)
    required_entries = index_tool_surface(required_surface)
    candidate_entries = index_tool_surface(candidate_surface)
    return false unless required_entries.keys == candidate_entries.keys

    required_entries.all? do |tool_name, required_entry|
      normalize_tool_entry_for_recovery(required_entry) == normalize_tool_entry_for_recovery(candidate_entries.fetch(tool_name))
    end
  end

  def index_tool_surface(tool_surface)
    Array(tool_surface).each_with_object({}) do |entry, out|
      out[entry.fetch("tool_name")] = entry.deep_dup
    end
  end

  def normalize_tool_entry_for_recovery(entry)
    normalized = deep_stringify(entry)
    return normalized unless normalized["tool_name"] == "subagent_spawn"

    profile_key_schema = normalized.dig("input_schema", "properties", "profile_key")
    return normalized unless profile_key_schema.is_a?(Hash)

    normalized["input_schema"]["properties"]["profile_key"] = profile_key_schema.except("enum", "description")
    normalized
  end

  def deep_stringify(value)
    case value
    when Hash
      value.each_with_object({}) do |(key, nested_value), out|
        out[key.to_s] = deep_stringify(nested_value)
      end
    when Array
      value.map { |item| deep_stringify(item) }
    else
      value
    end
  end

  def agent_installation_match
    return if agent.blank? || agent.installation_id == installation_id

    errors.add(:agent, "must belong to the same installation")
  end

  def document_installation_match
    document_associations.each do |association_name|
      document = public_send(association_name)
      next if document.blank? || document.installation_id == installation_id

      errors.add(association_name, "must belong to the same installation")
    end
  end

  def protocol_methods_contract_shape
    protocol_methods.each do |entry|
      unless entry.is_a?(Hash) && entry["method_id"].to_s.match?(METHOD_ID_PATTERN)
        errors.add(:protocol_methods_document, "must contain snake_case method_id entries")
        break
      end
    end
  end

  def feature_contract_shape
    feature_contract.each do |entry|
      unless entry.is_a?(Hash) && entry["feature_key"].to_s.match?(METHOD_ID_PATTERN)
        errors.add(:feature_contract_document, "must contain snake_case feature_key entries")
        break
      end

      unless entry["execution_mode"].to_s == "direct"
        errors.add(:feature_contract_document, "must contain supported execution_mode values")
        break
      end
    end
  end

  def tool_contract_shape
    tool_contract.each do |entry|
      unless entry.is_a?(Hash) && entry["tool_name"].to_s.match?(METHOD_ID_PATTERN)
        errors.add(:tool_contract_document, "must contain snake_case tool_name entries")
        break
      end

      unless TOOL_KINDS.include?(entry["tool_kind"])
        errors.add(:tool_contract_document, "must contain supported tool_kind values")
        break
      end
    end
  end

  def request_preparation_contract_shape
    contract = request_preparation_contract
    return if contract.blank?

    prompt_compaction = contract["prompt_compaction"]
    return if prompt_compaction.blank?

    unless prompt_compaction.is_a?(Hash)
      errors.add(:request_preparation_contract_document, "prompt_compaction must be a hash")
      return
    end

    consultation_mode = prompt_compaction["consultation_mode"].to_s
    unless consultation_mode.blank? || %w[direct_optional direct_required none].include?(consultation_mode)
      errors.add(:request_preparation_contract_document, "must contain supported consultation_mode values")
      return
    end

    workflow_execution = prompt_compaction["workflow_execution"].to_s
    unless workflow_execution.blank? || %w[supported unsupported].include?(workflow_execution)
      errors.add(:request_preparation_contract_document, "must contain supported workflow_execution values")
      return
    end

    lifecycle = prompt_compaction["lifecycle"].to_s
    return if lifecycle.blank? || lifecycle == "turn_scoped"

    errors.add(:request_preparation_contract_document, "must contain supported lifecycle values")
  end

  def tool_contract_reserved_prefix_policy
    tool_contract.each do |entry|
      next unless entry.is_a?(Hash)
      next unless entry["tool_name"].to_s.start_with?(RESERVED_CORE_MATRIX_PREFIX)
      next if entry["implementation_source"] == "core_matrix"

      errors.add(:tool_contract_document, "reserved core_matrix tool names may only be supplied by core_matrix implementations")
      break
    end
  end

  def document_associations
    %i[
      protocol_methods_document
      feature_contract_document
      request_preparation_contract_document
      tool_contract_document
      profile_policy_document
      canonical_config_schema_document
      conversation_override_schema_document
      workspace_agent_settings_schema_document
      default_workspace_agent_settings_document
      default_canonical_config_document
      reflected_surface_document
    ]
  end

  def payload_array(document)
    payload = document&.payload
    payload.is_a?(Array) ? payload.deep_dup : []
  end

  def payload_hash(document)
    payload = document&.payload
    payload.is_a?(Hash) ? payload.deep_dup : {}
  end
end
