require "test_helper"

class Conversations::Metadata::TitleBootstrapPolicyTest < ActiveSupport::TestCase
  test "workspace config overrides runtime canonical defaults" do
    context = create_workspace_context!
    context[:workspace].update!(
      config: {
        "metadata" => {
          "title_bootstrap" => {
            "enabled" => true,
            "mode" => "embedded_only",
          },
        },
      }
    )
    agent_definition_version = create_agent_definition_version!(
      installation: context[:installation],
      agent: context[:agent],
      default_canonical_config: {
        "metadata" => {
          "title_bootstrap" => {
            "enabled" => true,
            "mode" => "runtime_first",
          },
        },
      }
    )

    policy = Conversations::Metadata::TitleBootstrapPolicy.call(
      workspace: context[:workspace],
      agent_definition_version: agent_definition_version
    )

    assert_equal true, policy.fetch("enabled")
    assert_equal "embedded_only", policy.fetch("mode")
  end

  test "runtime canonical config is used when workspace override is absent" do
    context = create_workspace_context!
    context[:workspace].update!(config: {})
    agent_definition_version = create_agent_definition_version!(
      installation: context[:installation],
      agent: context[:agent],
      default_canonical_config: {
        "metadata" => {
          "title_bootstrap" => {
            "enabled" => false,
            "mode" => "embedded_only",
          },
        },
      }
    )

    policy = Conversations::Metadata::TitleBootstrapPolicy.call(
      workspace: context[:workspace],
      agent_definition_version: agent_definition_version
    )

    assert_equal false, policy.fetch("enabled")
    assert_equal "embedded_only", policy.fetch("mode")
  end

  test "built-in fallback is enabled runtime_first when no upstream config exists" do
    context = create_workspace_context!
    context[:workspace].update!(config: {})
    agent_definition_version = create_agent_definition_version!(
      installation: context[:installation],
      agent: context[:agent],
      default_canonical_config: {}
    )

    policy = Conversations::Metadata::TitleBootstrapPolicy.call(
      workspace: context[:workspace],
      agent_definition_version: agent_definition_version
    )

    assert_equal true, policy.fetch("enabled")
    assert_equal "runtime_first", policy.fetch("mode")
  end
end
