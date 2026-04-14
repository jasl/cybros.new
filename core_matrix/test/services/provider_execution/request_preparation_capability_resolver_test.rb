require "test_helper"

class ProviderExecution::RequestPreparationCapabilityResolverTest < ActiveSupport::TestCase
  test "resolves frozen prompt compaction capability from the dedicated request preparation contract" do
    installation = create_installation!
    agent = create_agent!(installation: installation)
    agent_definition_version = create_agent_definition_version!(
      installation: installation,
      agent: agent,
      request_preparation_contract: {
        "prompt_compaction" => {
          "consultation_mode" => "direct_optional",
          "workflow_execution" => "supported",
          "lifecycle" => "turn_scoped",
          "consultation_schema" => { "type" => "object" },
          "artifact_schema" => { "type" => "object" },
          "implementation_ref" => "fenix/prompt_compaction",
        },
      }
    )
    AgentConnection.where(agent: agent, lifecycle_state: "active").update_all(
      lifecycle_state: "stale",
      updated_at: Time.current
    )
    create_agent_connection!(
      installation: installation,
      agent: agent,
      agent_definition_version: agent_definition_version,
      lifecycle_state: "active"
    )

    capability = ProviderExecution::RequestPreparationCapabilityResolver.call(
      agent_definition_version: agent_definition_version
    )

    assert_equal true, capability.dig("prompt_compaction", "available")
    assert_equal "direct_optional", capability.dig("prompt_compaction", "consultation_mode")
    assert_equal "supported", capability.dig("prompt_compaction", "workflow_execution")
  end

  test "marks prompt compaction unavailable when the runtime is offline" do
    installation = create_installation!
    agent = create_agent!(installation: installation)
    agent_definition_version = create_agent_definition_version!(
      installation: installation,
      agent: agent,
      request_preparation_contract: {
        "prompt_compaction" => {
          "consultation_mode" => "direct_optional",
          "workflow_execution" => "supported",
          "lifecycle" => "turn_scoped",
          "consultation_schema" => { "type" => "object" },
          "artifact_schema" => { "type" => "object" },
          "implementation_ref" => "fenix/prompt_compaction",
        },
      }
    )
    AgentConnection.where(agent: agent, lifecycle_state: "active").update_all(
      lifecycle_state: "stale",
      updated_at: Time.current
    )

    capability = ProviderExecution::RequestPreparationCapabilityResolver.call(
      agent_definition_version: agent_definition_version
    )

    assert_equal false, capability.dig("prompt_compaction", "available")
  end
end
