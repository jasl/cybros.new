class RuntimeCapabilityContract
  DEFAULT_SUBAGENT_PROFILE_ALIAS = "default"

  RESERVED_SUBAGENT_TOOL_NAMES = %w[
    subagent_spawn
    subagent_send
    subagent_wait
    subagent_close
    subagent_list
  ].freeze

  def self.build(...)
    new(...)
  end

  def initialize(
    executor_program: nil,
    agent_program_version: nil,
    capability_snapshot: nil,
    executor_capability_payload: nil,
    executor_tool_catalog: nil,
    protocol_methods: nil,
    tool_catalog: nil,
    profile_catalog: nil,
    config_schema_snapshot: nil,
    conversation_override_schema_snapshot: nil,
    default_config_snapshot: nil,
    core_matrix_tool_catalog: []
  )
    @executor_program = executor_program
    @agent_program_version = agent_program_version || capability_snapshot
    @executor_capability_payload = normalize_hash(
      executor_capability_payload.nil? ? @executor_program&.capability_payload : executor_capability_payload
    )
    @executor_tool_catalog = normalize_array(
      executor_tool_catalog.nil? ? @executor_program&.tool_catalog : executor_tool_catalog
    )
    @protocol_methods = normalize_array(
      protocol_methods.nil? ? agent_program_version&.protocol_methods : protocol_methods
    )
    @program_tool_catalog = normalize_array(
      tool_catalog.nil? ? agent_program_version&.tool_catalog : tool_catalog
    )
    @profile_catalog = normalize_hash(
      profile_catalog.nil? ? agent_program_version&.profile_catalog : profile_catalog
    )
    @config_schema_snapshot = normalize_hash(
      config_schema_snapshot.nil? ? agent_program_version&.config_schema_snapshot : config_schema_snapshot
    )
    @conversation_override_schema_snapshot = normalize_hash(
      conversation_override_schema_snapshot.nil? ? agent_program_version&.conversation_override_schema_snapshot : conversation_override_schema_snapshot
    )
    @default_config_snapshot = normalize_hash(
      default_config_snapshot.nil? ? agent_program_version&.default_config_snapshot : default_config_snapshot
    )
    @core_matrix_tool_catalog = normalize_array(core_matrix_tool_catalog)
  end

  def executor_capability_payload
    @executor_capability_payload.deep_dup
  end

  def executor_tool_catalog
    normalize_tool_catalog(@executor_tool_catalog)
  end

  def protocol_methods
    @protocol_methods.deep_dup
  end

  def program_tool_catalog
    normalize_tool_catalog(@program_tool_catalog)
  end

  def config_schema_snapshot
    @config_schema_snapshot.deep_dup
  end

  def profile_catalog
    @profile_catalog.deep_dup
  end

  def conversation_override_schema_snapshot
    @conversation_override_schema_snapshot.deep_dup
  end

  def default_config_snapshot
    @default_config_snapshot.deep_dup
  end

  def program_version_fingerprint
    @agent_program_version&.fingerprint
  end

  def executor_plane
    {
      "control_plane" => "executor",
      "capability_payload" => executor_capability_payload,
      "tool_catalog" => executor_tool_catalog,
    }
  end

  def program_plane
    {
      "control_plane" => "program",
      "program_version_fingerprint" => program_version_fingerprint,
      "protocol_methods" => protocol_methods,
      "tool_catalog" => program_tool_catalog,
      "profile_catalog" => profile_catalog,
      "config_schema_snapshot" => config_schema_snapshot,
      "conversation_override_schema_snapshot" => conversation_override_schema_snapshot,
      "default_config_snapshot" => default_config_snapshot,
    }.compact
  end

  def effective_tool_catalog
    ordinary_entries = {}
    ordinary_order = []
    reserved_entries = {}
    reserved_order = []

    [@core_matrix_tool_catalog, executor_tool_catalog, program_tool_catalog].each do |catalog|
      catalog.each do |entry|
        tool_name = entry.fetch("tool_name")

        if reserved_core_matrix_tool?(tool_name)
          next if reserved_entries.key?(tool_name)

          reserved_entries[tool_name] = normalize_effective_tool_entry(
            entry,
            overlays: tool_policy_overlays
          )
          reserved_order << tool_name
          next
        end

        next if ordinary_entries.key?(tool_name)

        ordinary_entries[tool_name] = normalize_effective_tool_entry(
          entry,
          overlays: tool_policy_overlays
        )
        ordinary_order << tool_name
      end
    end

    reserved_order.map { |tool_name| reserved_entries.fetch(tool_name) } +
      ordinary_order.map { |tool_name| ordinary_entries.fetch(tool_name) }
  end

  def contract_payload(method_id: nil, reconciliation_report: nil)
    {
      "method_id" => method_id,
      "program_version_fingerprint" => program_version_fingerprint,
      "protocol_methods" => protocol_methods,
      "tool_catalog" => program_tool_catalog,
      "profile_catalog" => profile_catalog,
      "config_schema_snapshot" => config_schema_snapshot,
      "conversation_override_schema_snapshot" => conversation_override_schema_snapshot,
      "default_config_snapshot" => default_config_snapshot,
      "reconciliation_report" => reconciliation_report,
    }.compact
  end

  def capability_response(method_id:, executor_program_id:, executor_fingerprint:, reconciliation_report: nil)
    contract_payload(
      method_id: method_id,
      reconciliation_report: reconciliation_report
    ).merge(
      "executor_program_id" => executor_program_id,
      "executor_fingerprint" => executor_fingerprint,
      "executor_capability_payload" => executor_capability_payload,
      "executor_tool_catalog" => executor_tool_catalog,
      "program_plane" => program_plane,
      "executor_plane" => executor_plane,
      "effective_tool_catalog" => effective_tool_catalog
    ).compact
  end

  private

  def normalize_hash(value)
    return {} if value.blank?
    return value.deep_stringify_keys if value.is_a?(Hash)

    value.deep_dup
  end

  def normalize_array(value)
    Array(value).map { |entry| entry.deep_stringify_keys }
  end

  def reserved_core_matrix_tool?(tool_name)
    tool_name.start_with?("core_matrix__") || RESERVED_SUBAGENT_TOOL_NAMES.include?(tool_name)
  end

  def normalize_effective_tool_entry(entry, overlays: [])
    normalized_entry = entry.deep_dup
    normalized_entry["execution_policy"] = RuntimeCapabilities::ResolveToolExecutionPolicy.call(
      tool_entry: normalized_entry,
      overlays: overlays
    )
    normalized_entry
  end

  def normalize_tool_catalog(catalog)
    Array(catalog).map { |entry| normalize_effective_tool_entry(entry) }
  end

  def tool_policy_overlays
    Array(@default_config_snapshot["tool_policy_overlays"]).filter_map do |entry|
      entry.is_a?(Hash) ? entry.deep_stringify_keys : nil
    end
  end
end
