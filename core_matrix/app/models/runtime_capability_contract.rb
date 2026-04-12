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
    execution_runtime: nil,
    agent_definition_version: nil,
    execution_runtime_capability_payload: nil,
    execution_runtime_tool_catalog: nil,
    protocol_methods: nil,
    tool_catalog: nil,
    profile_catalog: nil,
    config_schema_snapshot: nil,
    conversation_override_schema_snapshot: nil,
    default_config_snapshot: nil,
    core_matrix_tool_catalog: []
  )
    @execution_runtime = execution_runtime
    @agent_definition_version = agent_definition_version
    runtime_version = @execution_runtime&.current_execution_runtime_version
    @execution_runtime_capability_payload = normalize_hash(
      execution_runtime_capability_payload.nil? ? runtime_version&.capability_payload : execution_runtime_capability_payload
    )
    @execution_runtime_tool_catalog = normalize_array(
      execution_runtime_tool_catalog.nil? ? runtime_version&.tool_catalog : execution_runtime_tool_catalog
    )
    @protocol_methods = normalize_array(
      protocol_methods.nil? ? @agent_definition_version&.protocol_methods : protocol_methods
    )
    @agent_tool_catalog = normalize_array(
      tool_catalog.nil? ? @agent_definition_version&.tool_contract : tool_catalog
    )
    @profile_catalog = normalize_hash(
      profile_catalog.nil? ? @agent_definition_version&.profile_policy : profile_catalog
    )
    @config_schema_snapshot = normalize_hash(
      config_schema_snapshot.nil? ? @agent_definition_version&.canonical_config_schema : config_schema_snapshot
    )
    @conversation_override_schema_snapshot = normalize_hash(
      conversation_override_schema_snapshot.nil? ? @agent_definition_version&.conversation_override_schema : conversation_override_schema_snapshot
    )
    @default_config_snapshot = normalize_hash(
      default_config_snapshot.nil? ? @agent_definition_version&.default_canonical_config : default_config_snapshot
    )
    @core_matrix_tool_catalog = normalize_array(core_matrix_tool_catalog)
  end

  def execution_runtime_capability_payload
    @execution_runtime_capability_payload.deep_dup
  end

  def execution_runtime_tool_catalog
    normalize_tool_catalog(@execution_runtime_tool_catalog)
  end

  def protocol_methods
    @protocol_methods.deep_dup
  end

  def agent_tool_catalog
    normalize_tool_catalog(@agent_tool_catalog)
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

  def agent_definition_fingerprint
    @agent_definition_version&.definition_fingerprint
  end

  def execution_runtime_plane
    {
      "control_plane" => "execution_runtime",
      "capability_payload" => execution_runtime_capability_payload,
      "tool_catalog" => execution_runtime_tool_catalog,
    }
  end

  def agent_plane
    {
      "control_plane" => "agent",
      "agent_definition_fingerprint" => agent_definition_fingerprint,
      "protocol_methods" => protocol_methods,
      "tool_catalog" => agent_tool_catalog,
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

    @core_matrix_tool_catalog.each do |entry|
      tool_name = entry.fetch("tool_name")
      next unless reserved_core_matrix_tool?(tool_name)
      next if reserved_entries.key?(tool_name)

      reserved_entries[tool_name] = normalize_effective_tool_entry(
        entry,
        overlays: tool_policy_overlays
      )
      reserved_order << tool_name
    end

    [execution_runtime_tool_catalog, agent_tool_catalog, @core_matrix_tool_catalog].each do |catalog|
      catalog.each do |entry|
        tool_name = entry.fetch("tool_name")

        if reserved_core_matrix_tool?(tool_name)
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
      "agent_definition_fingerprint" => agent_definition_fingerprint,
      "protocol_methods" => protocol_methods,
      "tool_catalog" => agent_tool_catalog,
      "profile_catalog" => profile_catalog,
      "config_schema_snapshot" => config_schema_snapshot,
      "conversation_override_schema_snapshot" => conversation_override_schema_snapshot,
      "default_config_snapshot" => default_config_snapshot,
      "reconciliation_report" => reconciliation_report,
    }.compact
  end

  def capability_response(method_id:, execution_runtime_id:, execution_runtime_fingerprint:, reconciliation_report: nil)
    contract_payload(
      method_id: method_id,
      reconciliation_report: reconciliation_report
    ).merge(
      "execution_runtime_id" => execution_runtime_id,
      "execution_runtime_fingerprint" => execution_runtime_fingerprint,
      "execution_runtime_capability_payload" => execution_runtime_capability_payload,
      "execution_runtime_tool_catalog" => execution_runtime_tool_catalog,
      "agent_plane" => agent_plane,
      "execution_runtime_plane" => execution_runtime_plane,
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
