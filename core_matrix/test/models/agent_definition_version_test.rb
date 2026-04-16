require "test_helper"

class AgentDefinitionVersionTest < ActiveSupport::TestCase
  test "generates and resolves a public id" do
    definition_version = create_agent_definition_version!

    assert definition_version.public_id.present?
    assert_equal definition_version, AgentDefinitionVersion.find_by_public_id!(definition_version.public_id)
  end

  test "stores immutable normalized definition documents on the version" do
    definition_version = create_agent_definition_version!(
      protocol_methods_document: create_json_document!(document_kind: "protocol_methods", payload: [{ "method_id" => "conversation_variables_mget" }]),
      tool_contract_document: create_json_document!(document_kind: "tool_contract", payload: [{ "tool_name" => "agent_lookup", "tool_kind" => "agent_observation" }]),
      profile_policy_document: create_json_document!(document_kind: "profile_policy", payload: { "main" => { "role_slot" => "main" } }),
      canonical_config_schema_document: create_json_document!(document_kind: "config_schema", payload: { "type" => "object" }),
      conversation_override_schema_document: create_json_document!(document_kind: "conversation_override_schema", payload: { "type" => "object" }),
      workspace_agent_settings_schema_document: create_json_document!(document_kind: "workspace_agent_settings_schema", payload: { "type" => "object" }),
      default_workspace_agent_settings_document: create_json_document!(document_kind: "default_workspace_agent_settings", payload: { "interactive" => { "profile_key" => "main" } }),
      default_canonical_config_document: create_json_document!(document_kind: "default_config", payload: { "interactive" => { "default_profile_key" => "main" } }),
      reflected_surface_document: create_json_document!(document_kind: "reflected_surface", payload: { "display_name" => "Fenix" })
    )

    assert_equal ["conversation_variables_mget"], definition_version.protocol_methods_document.payload.map { |entry| entry.fetch("method_id") }
    assert_equal ["agent_lookup"], definition_version.tool_contract_document.payload.map { |entry| entry.fetch("tool_name") }
    assert_equal "object", definition_version.workspace_agent_settings_schema_document.payload.fetch("type")
    assert_equal "main", definition_version.default_workspace_agent_settings_document.payload.dig("interactive", "profile_key")
    assert_equal "main", definition_version.default_canonical_config_document.payload.dig("interactive", "default_profile_key")
    assert_equal "Fenix", definition_version.reflected_surface_document.payload.fetch("display_name")
  end

  test "requires installation-local fingerprint uniqueness per agent" do
    installation = create_installation!
    agent = create_agent!(installation: installation)
    create_agent_definition_version!(
      installation: installation,
      agent: agent,
      definition_fingerprint: "definition-a"
    )

    duplicate = build_agent_definition_version(
      installation: installation,
      agent: agent,
      definition_fingerprint: "definition-a"
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:definition_fingerprint], "has already been taken"
  end
end
