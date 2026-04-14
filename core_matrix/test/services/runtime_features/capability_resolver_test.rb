require "test_helper"

class RuntimeFeatures::CapabilityResolverTest < ActiveSupport::TestCase
  test "resolves live title bootstrap capability from feature_contract" do
    context = create_workspace_context!
    agent_definition_version = create_agent_definition_version!(
      installation: context[:installation],
      agent: context[:agent],
      feature_contract: [
        {
          "feature_key" => "title_bootstrap",
          "execution_mode" => "direct",
          "lifecycle" => "live",
          "request_schema" => { "type" => "object" },
          "response_schema" => { "type" => "object" },
          "implementation_ref" => "fenix/title_bootstrap",
        },
      ]
    )
    context[:agent].agent_connections.update_all(
      lifecycle_state: "stale",
      updated_at: Time.current
    )
    create_agent_connection!(
      installation: context[:installation],
      agent: context[:agent],
      agent_definition_version: agent_definition_version
    )

    capability = RuntimeFeatures::CapabilityResolver.call(
      feature_key: "title_bootstrap",
      agent_definition_version: agent_definition_version
    )

    assert_equal true, capability.fetch("available")
    assert_equal "direct", capability.fetch("execution_mode")
    assert_equal "live", capability.fetch("lifecycle")
    assert_equal "fenix/title_bootstrap", capability.fetch("implementation_ref")
  end

  test "returns unavailable when the feature is not advertised" do
    context = create_workspace_context!

    capability = RuntimeFeatures::CapabilityResolver.call(
      feature_key: "title_bootstrap",
      agent_definition_version: context[:agent_definition_version]
    )

    assert_equal false, capability.fetch("available")
    assert_nil capability["execution_mode"]
  end
end
