class RuntimeCapabilityContract
  def self.build(...)
    new(...)
  end

  def initialize(
    execution_environment: nil,
    capability_snapshot: nil,
    environment_capability_payload: nil,
    environment_tool_catalog: nil,
    protocol_methods: nil,
    tool_catalog: nil,
    profile_catalog: nil,
    config_schema_snapshot: nil,
    conversation_override_schema_snapshot: nil,
    default_config_snapshot: nil,
    core_matrix_tool_catalog: []
  )
    @execution_environment = execution_environment
    @capability_snapshot = capability_snapshot
    @environment_capability_payload = normalize_hash(
      environment_capability_payload.nil? ? execution_environment&.capability_payload : environment_capability_payload
    )
    @environment_tool_catalog = normalize_array(
      environment_tool_catalog.nil? ? execution_environment&.tool_catalog : environment_tool_catalog
    )
    @protocol_methods = normalize_array(
      protocol_methods.nil? ? capability_snapshot&.protocol_methods : protocol_methods
    )
    @agent_tool_catalog = normalize_array(
      tool_catalog.nil? ? capability_snapshot&.tool_catalog : tool_catalog
    )
    @profile_catalog = normalize_hash(
      profile_catalog.nil? ? capability_snapshot&.profile_catalog : profile_catalog
    )
    @config_schema_snapshot = normalize_hash(
      config_schema_snapshot.nil? ? capability_snapshot&.config_schema_snapshot : config_schema_snapshot
    )
    @conversation_override_schema_snapshot = normalize_hash(
      conversation_override_schema_snapshot.nil? ? capability_snapshot&.conversation_override_schema_snapshot : conversation_override_schema_snapshot
    )
    @default_config_snapshot = normalize_hash(
      default_config_snapshot.nil? ? capability_snapshot&.default_config_snapshot : default_config_snapshot
    )
    @core_matrix_tool_catalog = normalize_array(core_matrix_tool_catalog)
  end

  def environment_capability_payload
    @environment_capability_payload.deep_dup
  end

  def environment_tool_catalog
    @environment_tool_catalog.deep_dup
  end

  def protocol_methods
    @protocol_methods.deep_dup
  end

  def agent_tool_catalog
    @agent_tool_catalog.deep_dup
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

  def agent_capabilities_version
    @capability_snapshot&.version
  end

  def conversation_attachment_upload?
    environment_capability_payload.fetch("conversation_attachment_upload", true) == true
  end

  def environment_plane
    {
      "runtime_plane" => "environment",
      "capability_payload" => environment_capability_payload,
      "tool_catalog" => environment_tool_catalog,
    }
  end

  def agent_plane
    {
      "runtime_plane" => "agent",
      "agent_capabilities_version" => agent_capabilities_version,
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

    [environment_tool_catalog, agent_tool_catalog, @core_matrix_tool_catalog].each do |catalog|
      catalog.each do |entry|
        tool_name = entry.fetch("tool_name")

        if reserved_core_matrix_tool?(tool_name)
          next if reserved_entries.key?(tool_name)

          reserved_entries[tool_name] = entry.deep_dup
          reserved_order << tool_name
          next
        end

        next if ordinary_entries.key?(tool_name)

        ordinary_entries[tool_name] = entry.deep_dup
        ordinary_order << tool_name
      end
    end

    reserved_order.map { |tool_name| reserved_entries.fetch(tool_name) } +
      ordinary_order.map { |tool_name| ordinary_entries.fetch(tool_name) }
  end

  def contract_payload(method_id: nil, reconciliation_report: nil)
    {
      "method_id" => method_id,
      "agent_capabilities_version" => agent_capabilities_version,
      "protocol_methods" => protocol_methods,
      "tool_catalog" => agent_tool_catalog,
      "profile_catalog" => profile_catalog,
      "config_schema_snapshot" => config_schema_snapshot,
      "conversation_override_schema_snapshot" => conversation_override_schema_snapshot,
      "default_config_snapshot" => default_config_snapshot,
      "reconciliation_report" => reconciliation_report,
    }.compact
  end

  def capability_response(method_id:, execution_environment_id:, environment_fingerprint:, reconciliation_report: nil)
    contract_payload(
      method_id: method_id,
      reconciliation_report: reconciliation_report
    ).merge(
      "execution_environment_id" => execution_environment_id,
      "environment_fingerprint" => environment_fingerprint,
      "environment_capability_payload" => environment_capability_payload,
      "environment_tool_catalog" => environment_tool_catalog,
      "agent_plane" => agent_plane,
      "environment_plane" => environment_plane,
      "effective_tool_catalog" => effective_tool_catalog
    )
  end

  def conversation_payload(execution_environment_id:, agent_deployment_id:)
    {
      "execution_environment_id" => execution_environment_id,
      "agent_deployment_id" => agent_deployment_id,
      "conversation_attachment_upload" => conversation_attachment_upload?,
      "tool_catalog" => effective_tool_catalog,
    }
  end

  private

  def normalize_hash(value)
    return {} if value.blank?

    value.deep_stringify_keys
  end

  def normalize_array(value)
    Array(value).map { |entry| entry.deep_stringify_keys }
  end

  def reserved_core_matrix_tool?(tool_name)
    tool_name.start_with?("core_matrix__")
  end
end
