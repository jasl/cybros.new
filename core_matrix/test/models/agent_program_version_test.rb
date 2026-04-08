require "test_helper"

class AgentProgramVersionTest < ActiveSupport::TestCase
  test "generates and resolves a public id" do
    agent_program_version = create_agent_program_version!

    assert agent_program_version.public_id.present?
    assert_equal agent_program_version, AgentProgramVersion.find_by_public_id!(agent_program_version.public_id)
  end

  test "stores immutable capability payloads directly on the version" do
    version = create_agent_program_version!(
      protocol_methods: [{ "method_id" => "conversation_variables_mget" }],
      tool_catalog: [{ "tool_name" => "agent_lookup", "tool_kind" => "agent_observation" }],
      profile_catalog: { "default" => { "temperature" => 0.2 } },
      config_schema_snapshot: { "type" => "object" },
      conversation_override_schema_snapshot: { "type" => "object" },
      default_config_snapshot: { "temperature" => 0.2 }
    )

    assert_equal ["conversation_variables_mget"], version.protocol_methods.map { |entry| entry.fetch("method_id") }
    assert_equal ["agent_lookup"], version.tool_catalog.map { |entry| entry.fetch("tool_name") }
    assert_equal 0.2, version.default_config_snapshot.fetch("temperature")
    assert_nil AgentProgramVersion.reflect_on_association(:executor_program)
  end

  test "requires installation-local fingerprint uniqueness" do
    installation = create_installation!
    program = create_agent_program!(installation: installation)
    create_agent_program_version!(
      installation: installation,
      agent_program: program,
      fingerprint: "version-a"
    )

    duplicate = AgentProgramVersion.new(
      installation: installation,
      agent_program: program,
      fingerprint: "version-a",
      protocol_version: "2026-04-03",
      sdk_version: "fenix-0.2.0",
      protocol_methods: [],
      tool_catalog: [],
      profile_catalog: {},
      config_schema_snapshot: {},
      conversation_override_schema_snapshot: {},
      default_config_snapshot: {}
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:fingerprint], "has already been taken"
  end
end
